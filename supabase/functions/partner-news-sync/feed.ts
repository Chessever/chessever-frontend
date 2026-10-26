/**
 * Partner news feeds: an RSS 2.0 document in, ChessEver partner articles
 * out. Pure (no Deno, no network, no dependencies) so the edge function and
 * the Node tests run the very same code.
 *
 * Partner HTML is never stored and never rendered. Each item's body
 * (`content:encoded`, else `description`) is converted here, once, into the
 * markdown the apps already render: paragraphs, links, emphasis, quotes,
 * lists, GFM tables, headings and pictures. Everything else (scripts,
 * styles, forms, embeds other than YouTube) is dropped. The picture that
 * opens the body becomes the cover and leaves the body.
 *
 * Only the opening half of an article is kept (EXCERPT_SHARE). The apps
 * show it and send the reader to the partner's site for the rest, so
 * ChessEver never stands in for the partner's own page.
 *
 * An item is kept only when its link is https on the partner's own site, so
 * a feed can never make the apps credit the partner with somebody else's
 * page. Pictures load only from the partner's asset hosts.
 */

export interface PartnerSource {
  id: string;
  /** `https://rookreview.com` */
  siteUrl: string;
  /** Hosts pictures may come from (`rookreview.b-cdn.net`, ...). */
  assetHosts: readonly string[];
}

export interface PartnerArticle {
  guid: string;
  url: string;
  title: string;
  summary: string;
  /**
   * The article's opening half as markdown, paragraphs separated by one
   * blank line. The rest is read on the partner's site.
   */
  content: string;
  imageUrl: string | null;
  /** ISO 8601, never later than the parse time. */
  publishedAt: string;
}

export interface ParseOptions {
  now?: Date;
  maxItems?: number;
  /** Share of each article kept; EXCERPT_SHARE unless a test asks for all. */
  share?: number;
}

/**
 * How much of a partner's article ChessEver shows, by its words. The apps
 * end the excerpt with a link to the article on the partner's site.
 */
export const EXCERPT_SHARE = 0.5;

const MAX_TITLE = 400;
const MAX_SUMMARY = 600;
const MAX_GUID = 512;
const MAX_CONTENT = 200_000;
const MAX_TABLE_ROWS = 200;
const MAX_TABLE_COLUMNS = 12;
/** A date further ahead than this is junk, not a scheduled post. */
const FUTURE_SLACK_MS = 24 * 60 * 60 * 1000;

// ---------------------------------------------------------------------------
// Markup tree
// ---------------------------------------------------------------------------

export interface MarkupElement {
  name: string;
  attrs: Record<string, string>;
  children: MarkupNode[];
}

export type MarkupNode = MarkupElement | string;

const VOID_ELEMENTS = new Set([
  "area", "base", "br", "col", "embed", "hr", "img", "input", "link", "meta",
  "param", "source", "track", "wbr",
]);
const RAW_TEXT_ELEMENTS = new Set(["script", "style", "textarea", "title"]);
/** Opening one of these closes an open `<p>`, as browsers do. */
const CLOSES_PARAGRAPH = new Set([
  "address", "article", "aside", "blockquote", "details", "div", "dl",
  "fieldset", "figcaption", "figure", "footer", "form", "h1", "h2", "h3", "h4",
  "h5", "h6", "header", "hr", "main", "nav", "ol", "p", "pre", "section",
  "table", "ul",
]);

const TAG =
  /<(\/?)([A-Za-z][\w:.-]*)((?:\s+[^\s"'>\/=]+(?:\s*=\s*(?:"[^"]*"|'[^']*'|[^\s"'=<>`]+))?)*)\s*(\/?)>/y;
const ATTR = /([^\s"'>\/=]+)(?:\s*=\s*(?:"([^"]*)"|'([^']*)'|([^\s"'=<>`]+)))?/g;

function parseAttrs(source: string): Record<string, string> {
  const attrs: Record<string, string> = {};
  for (const match of source.matchAll(ATTR)) {
    const name = match[1].toLowerCase();
    if (name in attrs) continue;
    attrs[name] = decodeEntities(match[2] ?? match[3] ?? match[4] ?? "");
  }
  return attrs;
}

/**
 * A forgiving parser for both the feed (XML, [html] false) and the article
 * bodies (HTML). Unknown or unmatched closing tags are ignored, a stray `<`
 * is text, and comments and processing instructions vanish. CDATA becomes
 * text verbatim.
 */
export function parseMarkup(input: string, html: boolean): MarkupElement {
  const root: MarkupElement = { name: "#root", attrs: {}, children: [] };
  const stack: MarkupElement[] = [root];
  const top = () => stack[stack.length - 1];
  const text = (value: string) => {
    if (value) top().children.push(value);
  };
  const closeTo = (name: string) => {
    for (let i = stack.length - 1; i > 0; i--) {
      if (stack[i].name === name) {
        stack.length = i;
        return;
      }
    }
  };

  let i = 0;
  while (i < input.length) {
    const lt = input.indexOf("<", i);
    if (lt < 0) {
      text(decodeEntities(input.slice(i)));
      break;
    }
    if (lt > i) text(decodeEntities(input.slice(i, lt)));

    if (input.startsWith("<!--", lt)) {
      const end = input.indexOf("-->", lt + 4);
      i = end < 0 ? input.length : end + 3;
      continue;
    }
    if (input.startsWith("<![CDATA[", lt)) {
      const end = input.indexOf("]]>", lt + 9);
      text(input.slice(lt + 9, end < 0 ? input.length : end));
      i = end < 0 ? input.length : end + 3;
      continue;
    }
    if (input.startsWith("<?", lt) || input.startsWith("<!", lt)) {
      const end = input.indexOf(">", lt);
      i = end < 0 ? input.length : end + 1;
      continue;
    }

    TAG.lastIndex = lt;
    const tag = TAG.exec(input);
    if (!tag) {
      text("<");
      i = lt + 1;
      continue;
    }
    i = TAG.lastIndex;
    const closing = tag[1] === "/";
    const name = html ? tag[2].toLowerCase() : tag[2];

    if (closing) {
      closeTo(name);
      continue;
    }

    if (html) {
      if (CLOSES_PARAGRAPH.has(name) && top().name === "p") stack.pop();
      if (name === "li") closeTo2(stack, "li", ["ul", "ol"]);
      if (name === "tr") closeTo2(stack, "tr", ["table", "thead", "tbody", "tfoot"]);
      if (name === "td" || name === "th") {
        closeTo2(stack, "td", ["tr", "table"]);
        closeTo2(stack, "th", ["tr", "table"]);
      }
    }

    const element: MarkupElement = {
      name,
      attrs: parseAttrs(tag[3]),
      children: [],
    };
    top().children.push(element);

    if (html && RAW_TEXT_ELEMENTS.has(name)) {
      const end = input.toLowerCase().indexOf(`</${name}`, i);
      const raw = input.slice(i, end < 0 ? input.length : end);
      if (name === "title" || name === "textarea") {
        element.children.push(decodeEntities(raw));
      }
      if (end < 0) break;
      const close = input.indexOf(">", end);
      i = close < 0 ? input.length : close + 1;
      continue;
    }

    const selfClosing = tag[4] === "/" || (html && VOID_ELEMENTS.has(name));
    if (!selfClosing) stack.push(element);
  }
  return root;
}

/** Closes an open [name] unless one of [boundaries] is nearer. */
function closeTo2(
  stack: MarkupElement[],
  name: string,
  boundaries: readonly string[],
): void {
  for (let i = stack.length - 1; i > 0; i--) {
    const open = stack[i].name;
    if (open === name) {
      stack.length = i;
      return;
    }
    if (boundaries.includes(open)) return;
  }
}

const NAMED_ENTITIES: Record<string, string> = {
  amp: "&", lt: "<", gt: ">", quot: '"', apos: "'", nbsp: " ",
  ndash: "–", mdash: "—", hellip: "…", lsquo: "‘",
  rsquo: "’", sbquo: "‚", ldquo: "“", rdquo: "”",
  bdquo: "„", laquo: "«", raquo: "»", lsaquo: "‹",
  rsaquo: "›", copy: "©", reg: "®", trade: "™",
  deg: "°", middot: "·", bull: "•", times: "×",
  divide: "÷", minus: "−", plusmn: "±", frac12: "½",
  frac14: "¼", frac34: "¾", sup2: "²", sup3: "³",
  prime: "′", Prime: "″", euro: "€", pound: "£",
  yen: "¥", cent: "¢", sect: "§", para: "¶",
  shy: "­", zwj: "‍", zwnj: "‌", thinsp: " ",
  ensp: " ", emsp: " ", iexcl: "¡", iquest: "¿",
  aacute: "á", Aacute: "Á", agrave: "à", acirc: "â",
  auml: "ä", Auml: "Ä", aring: "å", atilde: "ã",
  ccedil: "ç", Ccedil: "Ç", eacute: "é", Eacute: "É",
  egrave: "è", ecirc: "ê", euml: "ë", iacute: "í",
  igrave: "ì", icirc: "î", iuml: "ï", ntilde: "ñ",
  Ntilde: "Ñ", oacute: "ó", Oacute: "Ó", ograve: "ò",
  ocirc: "ô", ouml: "ö", Ouml: "Ö", otilde: "õ",
  oslash: "ø", Oslash: "Ø", szlig: "ß", uacute: "ú",
  Uacute: "Ú", ugrave: "ù", ucirc: "û", uuml: "ü",
  Uuml: "Ü", yacute: "ý", yuml: "ÿ", scaron: "š",
  Scaron: "Š", zcaron: "ž", Zcaron: "Ž", ccaron: "č",
  Ccaron: "Č",
};

export function decodeEntities(value: string): string {
  if (!value.includes("&")) return value;
  return value.replace(
    /&(?:#(\d{1,7})|#[xX]([0-9A-Fa-f]{1,6})|([A-Za-z][A-Za-z0-9]{1,31}));/g,
    (whole, decimal?: string, hex?: string, name?: string) => {
      if (name !== undefined) return NAMED_ENTITIES[name] ?? whole;
      const code = decimal !== undefined
        ? Number.parseInt(decimal, 10)
        : Number.parseInt(hex!, 16);
      const valid = code > 0 && code <= 0x10ffff &&
        !(code >= 0xd800 && code <= 0xdfff);
      return valid ? String.fromCodePoint(code) : "�";
    },
  );
}

function localName(name: string): string {
  const colon = name.lastIndexOf(":");
  return (colon < 0 ? name : name.slice(colon + 1)).toLowerCase();
}

function childElements(element: MarkupElement): MarkupElement[] {
  return element.children.filter((c): c is MarkupElement =>
    typeof c !== "string"
  );
}

function findAll(
  element: MarkupElement,
  match: (e: MarkupElement) => boolean,
  out: MarkupElement[] = [],
): MarkupElement[] {
  for (const child of childElements(element)) {
    if (match(child)) {
      out.push(child);
    } else {
      findAll(child, match, out);
    }
  }
  return out;
}

/** Concatenated text of [node], tags removed. */
export function textContent(node: MarkupNode): string {
  if (typeof node === "string") return node;
  return node.children.map(textContent).join("");
}

function collapse(value: string): string {
  return value.replace(/[\s ]+/g, " ").trim();
}

function truncate(value: string, max: number): string {
  if (value.length <= max) return value;
  const cut = value.slice(0, max - 1);
  const space = cut.lastIndexOf(" ");
  return `${(space > max * 0.6 ? cut.slice(0, space) : cut).trimEnd()}…`;
}

// ---------------------------------------------------------------------------
// URLs
// ---------------------------------------------------------------------------

function hostMatches(host: string, allowed: string): boolean {
  return host === allowed || host.endsWith(`.${allowed}`);
}

/** [href] resolved against [base]; null unless http(s) without credentials. */
export function resolveHttpUrl(href: string, base?: string): URL | null {
  const trimmed = href.trim();
  if (!trimmed || trimmed.startsWith("#")) return null;
  let url: URL;
  try {
    url = base ? new URL(trimmed, base) : new URL(trimmed);
  } catch {
    return null;
  }
  if (url.protocol !== "https:" && url.protocol !== "http:") return null;
  if (url.username || url.password) return null;
  return url;
}

/** A markdown link destination that survives any parser. */
function markdownUrl(url: URL): string {
  return url.href.replace(/[ ()<>\\]/g, (c) =>
    `%${c.charCodeAt(0).toString(16).toUpperCase().padStart(2, "0")}`
  );
}

/** An https picture on one of [assetHosts]; null otherwise. */
export function assetUrl(
  src: string | undefined,
  base: string,
  assetHosts: readonly string[],
): string | null {
  if (!src) return null;
  const url = resolveHttpUrl(src, base);
  if (!url) return null;
  if (url.protocol === "http:") url.protocol = "https:";
  if (url.port) return null;
  const host = url.hostname.toLowerCase();
  if (!assetHosts.some((allowed) => hostMatches(host, allowed))) return null;
  return url.href;
}

/** The 11-character YouTube id an embed or watch URL points at. */
export function youtubeId(src: string | undefined): string | null {
  if (!src) return null;
  const url = resolveHttpUrl(src.startsWith("//") ? `https:${src}` : src);
  if (!url) return null;
  const host = url.hostname.toLowerCase().replace(/^www\./, "");
  let id: string | null = null;
  if (host === "youtu.be") {
    id = url.pathname.slice(1);
  } else if (
    host === "youtube.com" || host === "m.youtube.com" ||
    host === "youtube-nocookie.com"
  ) {
    const embed = url.pathname.match(/^\/(?:embed|shorts|live)\/([^/?#]+)/);
    id = embed ? embed[1] : url.searchParams.get("v");
  }
  return id && /^[A-Za-z0-9_-]{11}$/.test(id) ? id : null;
}

// ---------------------------------------------------------------------------
// HTML -> markdown
// ---------------------------------------------------------------------------

interface ConvertContext {
  base: string;
  assetHosts: readonly string[];
}

/** Text that reads the same once a markdown parser has seen it. */
function escapeMarkdown(value: string): string {
  return value
    .replace(/[\\`*_[\]<>|~]/g, "\\$&")
    .replace(/&(?=#?[A-Za-z0-9]+;)/g, "\\&");
}

/** Escapes what would start a heading, list, quote or rule. */
function escapeLineStart(line: string): string {
  return line
    .replace(/^(\d{1,9})([.)])(?=\s|$)/, "$1\\$2")
    .replace(/^([#=+-])/, "\\$1");
}

/** Wraps [inner] in [marker], keeping edge spaces outside it. */
function wrap(inner: string, marker: string): string {
  const match = inner.match(/^(\s*)([\s\S]*?)(\s*)$/)!;
  if (!match[2]) return inner;
  return `${match[1]}${marker}${match[2]}${marker}${match[3]}`;
}

/** Stands in for `<br>` until whitespace is collapsed. */
const BREAK = "\u0000";

const DROPPED_ELEMENTS = new Set([
  "applet", "audio", "button", "canvas", "datalist", "embed", "form", "head",
  "input", "link", "map", "meta", "noscript", "object", "script", "select",
  "style", "svg", "template", "textarea", "title", "video", "math",
]);
const BLOCK_CONTAINERS = new Set([
  "address", "article", "aside", "body", "center", "dd", "details", "div",
  "dl", "dt", "fieldset", "figure", "footer", "header", "html", "main", "nav",
  "p", "section", "summary", "#root",
]);
const BLOCK_ELEMENTS = new Set([
  ...BLOCK_CONTAINERS, "blockquote", "figcaption", "h1", "h2", "h3", "h4",
  "h5", "h6", "hr", "iframe", "img", "li", "ol", "picture", "pre", "table",
  "ul",
]);

class Blocks {
  readonly out: string[] = [];
  private inline = "";

  private readonly ctx: ConvertContext;

  constructor(ctx: ConvertContext) {
    this.ctx = ctx;
  }

  addInline(value: string) {
    this.inline += value;
  }

  flush() {
    const paragraph = this.inline
      .replace(/[ \t\r\n\f ]+/g, " ")
      .replace(new RegExp(`\\s*${BREAK}\\s*`, "g"), BREAK)
      .replace(new RegExp(`^${BREAK}+|${BREAK}+$`, "g"), "")
      .trim();
    this.inline = "";
    if (!paragraph || !/[^\s\\*~]/.test(paragraph.replaceAll(BREAK, ""))) {
      return;
    }
    this.out.push(
      paragraph
        .split(BREAK)
        .map((line) => escapeLineStart(line.trim()))
        .join("\\\n"),
    );
  }

  push(block: string) {
    this.flush();
    if (block.trim()) this.out.push(block);
  }

  walk(nodes: readonly MarkupNode[]) {
    for (const node of nodes) this.node(node);
  }

  node(node: MarkupNode) {
    if (typeof node === "string") {
      this.addInline(escapeMarkdown(node));
      return;
    }
    const name = node.name;
    if (DROPPED_ELEMENTS.has(name)) return;
    if (name === "a" && !collapse(textContent(node))) {
      // A linked picture is the picture.
      const img = findAll(node, (e) => e.name === "img")[0];
      if (img) this.image(img);
      return;
    }
    if (!BLOCK_ELEMENTS.has(name)) {
      this.addInline(this.inlineOf(node));
      return;
    }
    switch (name) {
      case "h1":
      case "h2":
      case "h3":
      case "h4":
      case "h5":
      case "h6": {
        const text = this.lineOf(node.children);
        const level = name === "h1" || name === "h2"
          ? "##"
          : name === "h3"
          ? "###"
          : "####";
        if (text) this.push(`${level} ${text}`);
        return;
      }
      case "blockquote": {
        const inner = this.nested(node.children, true);
        if (inner.length) {
          this.push(
            inner
              .map((block) =>
                block.split("\n").map((line) => `> ${line}`.trimEnd()).join(
                  "\n",
                )
              )
              .join("\n>\n"),
          );
        }
        return;
      }
      case "figcaption": {
        const text = this.lineOf(node.children);
        if (text) this.push(wrap(text, "*"));
        return;
      }
      case "ul":
      case "ol":
        this.push(this.list(node).join("\n"));
        return;
      case "li": {
        // A list item outside any list.
        const text = this.lineOf(node.children);
        if (text) this.push(`- ${escapeLineStart(text)}`);
        return;
      }
      case "table":
        this.push(this.table(node));
        return;
      case "pre": {
        const code = textContent(node).replace(/^\n/, "").replace(/\s+$/, "");
        if (!code) return;
        const run = Math.max(2, ...[...code.matchAll(/`+/g)].map((m) => m[0].length));
        const fence = "`".repeat(run + 1);
        this.push(`${fence}\n${code}\n${fence}`);
        return;
      }
      case "hr":
        this.push("---");
        return;
      case "img":
        this.image(node);
        return;
      case "picture": {
        const img = findAll(node, (e) => e.name === "img")[0];
        if (img) this.image(img);
        return;
      }
      case "iframe": {
        const id = youtubeId(node.attrs.src);
        if (id) this.push(`<!-- news-youtube: ${id} -->`);
        return;
      }
      default:
        // Block containers. Inside a quote a footer or cite is the speaker.
        this.flush();
        this.walk(node.children);
        this.flush();
    }
  }

  image(node: MarkupElement) {
    const src = assetUrl(
      node.attrs.src ?? node.attrs["data-src"],
      this.ctx.base,
      this.ctx.assetHosts,
    );
    if (!src) return;
    const alt = escapeMarkdown(collapse(node.attrs.alt ?? ""));
    this.push(`![${alt}](${markdownUrl(new URL(src))})`);
  }

  /** Blocks of [nodes] on their own; [quote] styles a footer as a byline. */
  nested(nodes: readonly MarkupNode[], quote: boolean): string[] {
    const inner = new Blocks(this.ctx);
    for (const node of nodes) {
      if (
        quote && typeof node !== "string" &&
        (node.name === "footer" || node.name === "cite")
      ) {
        const text = inner.lineOf(node.children);
        if (text) inner.push(wrap(text, "*"));
      } else {
        inner.node(node);
      }
    }
    inner.flush();
    return inner.out;
  }

  /** [nodes] as one line of inline markdown; nested blocks run together. */
  lineOf(nodes: readonly MarkupNode[]): string {
    return nodes
      .map((node) => (typeof node === "string"
        ? escapeMarkdown(node)
        : this.inlineOf(node)))
      .join("")
      .replaceAll(BREAK, " ")
      .replace(/[ \t\r\n\f ]+/g, " ")
      .trim();
  }

  inlineOf(node: MarkupElement): string {
    const name = node.name;
    if (DROPPED_ELEMENTS.has(name)) return "";
    if (name === "br") return BREAK;
    if (name === "img" || name === "iframe" || name === "picture") {
      // Pictures are blocks of their own; inline, only the alt text stays.
      return name === "img" ? escapeMarkdown(collapse(node.attrs.alt ?? "")) : "";
    }
    const inner = node.children
      .map((child) => (typeof child === "string"
        ? escapeMarkdown(child)
        : BLOCK_ELEMENTS.has(child.name)
        ? ` ${this.lineOf([child])} `
        : this.inlineOf(child)))
      .join("");
    switch (name) {
      case "a": {
        const url = resolveHttpUrl(node.attrs.href ?? "", this.ctx.base);
        const text = inner.replaceAll(BREAK, " ");
        if (!url || !text.trim()) return text;
        const match = text.match(/^(\s*)([\s\S]*?)(\s*)$/)!;
        return `${match[1]}[${match[2]}](${markdownUrl(url)})${match[3]}`;
      }
      case "strong":
      case "b":
        return wrap(inner, "**");
      case "em":
      case "i":
      case "cite":
      case "dfn":
        return wrap(inner, "*");
      case "del":
      case "s":
      case "strike":
        return wrap(inner, "~~");
      case "code":
      case "kbd":
      case "samp":
      case "tt": {
        const code = collapse(textContent(node));
        if (!code) return "";
        const run = Math.max(0, ...[...code.matchAll(/`+/g)].map((m) => m[0].length));
        const tick = "`".repeat(run + 1);
        const pad = code.startsWith("`") || code.endsWith("`") ? " " : "";
        return `${tick}${pad}${code}${pad}${tick}`;
      }
      case "q":
        return `“${inner}”`;
      default:
        return inner;
    }
  }

  list(node: MarkupElement): string[] {
    const ordered = node.name === "ol";
    const start = Number.parseInt(node.attrs.start ?? "1", 10);
    let number = Number.isFinite(start) && start >= 0 ? start : 1;
    const lines: string[] = [];
    for (const item of childElements(node)) {
      if (item.name !== "li") {
        if (item.name === "ul" || item.name === "ol") lines.push(...this.list(item));
        continue;
      }
      // Nested lists are flattened after their item: the apps collapse
      // indentation, so a nested level could not survive anyway.
      const nested = item.children.filter((c): c is MarkupElement =>
        typeof c !== "string" && (c.name === "ul" || c.name === "ol")
      );
      const text = this.lineOf(
        item.children.filter((c) => !nested.includes(c as MarkupElement)),
      );
      if (text) {
        const line = escapeLineStart(text);
        lines.push(ordered ? `${number++}. ${line}` : `- ${line}`);
      }
      for (const list of nested) lines.push(...this.list(list));
    }
    return lines;
  }

  table(node: MarkupElement): string {
    const rows = findAll(node, (e) => e.name === "tr" || e.name === "table")
      .filter((e) => e.name === "tr")
      .slice(0, MAX_TABLE_ROWS)
      .map((row) =>
        childElements(row)
          .filter((cell) => cell.name === "td" || cell.name === "th")
          .slice(0, MAX_TABLE_COLUMNS)
          .map((cell) => this.lineOf(cell.children))
      )
      .filter((cells) => cells.some((cell) => cell.length > 0));
    if (rows.length === 0) return "";
    const columns = Math.max(...rows.map((cells) => cells.length));
    const line = (cells: string[]) =>
      `| ${
        Array.from({ length: columns }, (_, i) => cells[i] ?? "").join(" | ")
      } |`;
    return [
      line(rows[0]),
      line(Array.from({ length: columns }, () => "---")),
      ...rows.slice(1).map(line),
    ].join("\n");
  }
}

/**
 * [html] as ChessEver article markdown blocks, and the picture that opened
 * it (now the cover, no longer in the body). [base] resolves relative links.
 */
export function htmlToBlocks(
  html: string,
  base: string,
  assetHosts: readonly string[],
): { blocks: string[]; leadImage: string | null } {
  const blocks = new Blocks({ base, assetHosts });
  blocks.walk(parseMarkup(html, true).children);
  blocks.flush();
  const out = blocks.out;

  let leadImage: string | null = null;
  const lead = out[0]?.match(/^!\[(?:\\.|[^\]\\])*\]\(([^)\s]+)\)$/);
  if (lead) {
    leadImage = lead[1];
    out.shift();
  }
  return { blocks: out, leadImage };
}

/** Blocks as one markdown document, at most MAX_CONTENT long. */
function joinBlocks(blocks: readonly string[]): string {
  let markdown = "";
  for (const block of blocks) {
    const next = markdown ? `${markdown}\n\n${block}` : block;
    if (next.length > MAX_CONTENT) break;
    markdown = next;
  }
  return markdown;
}

/** [html] as one ChessEver article markdown document; see htmlToBlocks. */
export function htmlToMarkdown(
  html: string,
  base: string,
  assetHosts: readonly string[],
): { markdown: string; leadImage: string | null } {
  const { blocks, leadImage } = htmlToBlocks(html, base, assetHosts);
  return { markdown: joinBlocks(blocks), leadImage };
}

// ---------------------------------------------------------------------------
// Excerpt
// ---------------------------------------------------------------------------

/** Letters and digits a reader sees in [markdown]; links count their text. */
export function readableLength(markdown: string): number {
  const text = markdown
    .replace(/<!--[\s\S]*?-->/g, "")
    .replace(/!\[(?:\\.|[^\]\\])*\]\([^)\s]*\)/g, "")
    .replace(/\]\([^)\s]*\)/g, "]");
  return text.match(/[\p{L}\p{N}]/gu)?.length ?? 0;
}

/** True unless [markdown] stops inside a link, code span or emphasis. */
function closed(markdown: string): boolean {
  const plain = markdown
    .replace(/\\./g, "")
    .replace(/\[[^\]]*\]\([^)\s]*\)/g, "");
  if (/[[\]]/.test(plain)) return false;
  const count = (pattern: RegExp, text = plain) =>
    text.match(pattern)?.length ?? 0;
  return count(/`+/g) % 2 === 0 &&
    count(/~~/g) % 2 === 0 &&
    count(/\*\*/g) % 2 === 0 &&
    count(/\*/g, plain.replaceAll("**", "")) % 2 === 0;
}

/** Where sentences end in a line of inline markdown. */
const SENTENCE_END = /[.!?…]["'”’)*_~]*(?=\s|\\\n|$)/g;

/**
 * The longest run of whole sentences opening [text] that reads within
 * [budget] letters, or the first sentence when [first] and none fits.
 */
function sentencesWithin(text: string, budget: number, first = false): string | null {
  let best: string | null = null;
  for (const match of text.matchAll(SENTENCE_END)) {
    const prefix = text.slice(0, (match.index ?? 0) + match[0].length);
    if (!closed(prefix)) continue;
    if (readableLength(prefix) > budget) return best ?? (first ? prefix : null);
    best = prefix;
  }
  return best;
}

const QUOTE_PARAGRAPHS = "\n>\n";

function isQuote(block: string): boolean {
  return block.startsWith(">");
}

function isList(block: string): boolean {
  return /^(?:- |\d{1,9}\. )/.test(block);
}

/** A paragraph of running text, the only kind cut between its sentences. */
function isProse(block: string): boolean {
  return !/^(?:#|\||```|~~~|!\[|<!--|---$|> ?|- |\d{1,9}\. )/.test(block);
}

/**
 * Text that may close an excerpt: not a picture, video, heading or rule,
 * nor a line introducing what comes next ("The standings are:").
 */
function endsOnWords(block: string): boolean {
  return !/^(?:#|!\[|<!--|---$)/.test(block) && !/:\s*$/.test(block);
}

/** As much of [block] as reads within [budget], or null for none of it. */
function cutBlock(block: string, budget: number): string | null {
  if (isQuote(block)) {
    const kept: string[] = [];
    let left = budget;
    for (const paragraph of block.split(QUOTE_PARAGRAPHS)) {
      const length = readableLength(paragraph);
      if (length <= left) {
        kept.push(paragraph);
        left -= length;
        continue;
      }
      const text = paragraph.replace(/^> ?/gm, "");
      const part = isProse(text) ? sentencesWithin(text, left) : null;
      if (part) kept.push(part.split("\n").map((line) => `> ${line}`).join("\n"));
      break;
    }
    return kept.length ? kept.join(QUOTE_PARAGRAPHS) : null;
  }
  if (block.startsWith("|")) {
    // The header and its rule, then whole rows.
    const [header, rule, ...rows] = block.split("\n");
    const kept: string[] = [];
    let left = budget - readableLength(header);
    for (const row of rows) {
      const length = readableLength(row);
      if (length > left) break;
      kept.push(row);
      left -= length;
    }
    return kept.length ? [header, rule, ...kept].join("\n") : null;
  }
  if (isList(block)) {
    const kept: string[] = [];
    let left = budget;
    for (const line of block.split("\n")) {
      const length = readableLength(line);
      if (length > left) break;
      kept.push(line);
      left -= length;
    }
    return kept.length ? kept.join("\n") : null;
  }
  return isProse(block) ? sentencesWithin(block, budget) : null;
}

/**
 * The opening [share] of an article's blocks, by readable letters: whole
 * blocks while they fit, then the next one cut between sentences (between
 * paragraphs in a quote, items in a list, rows in a table). It ends on
 * words, never inside a link or emphasis. An article too short to cut
 * keeps its first sentence.
 */
export function excerptBlocks(
  blocks: readonly string[],
  share = EXCERPT_SHARE,
): string[] {
  if (share >= 1) return [...blocks];
  const total = blocks.reduce((sum, block) => sum + readableLength(block), 0);
  const budget = total * share;
  const kept: string[] = [];
  let used = 0;
  for (const block of blocks) {
    const length = readableLength(block);
    if (used + length <= budget) {
      kept.push(block);
      used += length;
      continue;
    }
    const part = cutBlock(block, budget - used);
    if (part) kept.push(part);
    break;
  }
  while (kept.length && !endsOnWords(kept[kept.length - 1])) kept.pop();
  if (kept.some((block) => readableLength(block) > 0)) return kept;

  const opening = blocks.find((block) => isProse(block) && readableLength(block) > 0);
  if (!opening) return blocks.slice(0, 1);
  return [sentencesWithin(opening, budget, true) ?? opening];
}

/** The readable text of an HTML fragment, on one line. */
export function htmlToText(html: string): string {
  const root = parseMarkup(html, true);
  const parts: string[] = [];
  const visit = (node: MarkupNode) => {
    if (typeof node === "string") {
      parts.push(node);
      return;
    }
    if (DROPPED_ELEMENTS.has(node.name)) return;
    if (node.name === "br" || BLOCK_ELEMENTS.has(node.name)) parts.push(" ");
    node.children.forEach(visit);
    if (BLOCK_ELEMENTS.has(node.name)) parts.push(" ");
  };
  root.children.forEach(visit);
  return collapse(parts.join(""));
}

// ---------------------------------------------------------------------------
// RSS
// ---------------------------------------------------------------------------

/**
 * The first child named one of [names] (lower case). A prefixed name must
 * match exactly; `encoded` matches `content:encoded` under any prefix.
 */
function field(item: MarkupElement, ...names: string[]): MarkupElement | null {
  for (const name of names) {
    const found = childElements(item).find((child) => {
      const qualified = child.name.toLowerCase();
      return qualified === name ||
        (name === "encoded" && localName(qualified) === "encoded");
    });
    if (found) return found;
  }
  return null;
}

function fieldText(item: MarkupElement, ...names: string[]): string {
  const found = field(item, ...names);
  return found ? textContent(found).trim() : "";
}

/** A picture the item names outside its body (enclosure, media:*). */
function itemImage(
  item: MarkupElement,
  base: string,
  assetHosts: readonly string[],
): string | null {
  for (const child of childElements(item)) {
    const name = child.name.toLowerCase();
    const isImage = name === "enclosure"
      ? (child.attrs.type ?? "").startsWith("image/")
      : name === "media:thumbnail" ||
        (name === "media:content" &&
          (child.attrs.medium === "image" ||
            (child.attrs.type ?? "").startsWith("image/")));
    if (!isImage) continue;
    const url = assetUrl(child.attrs.url, base, assetHosts);
    if (url) return url;
  }
  return null;
}

/**
 * The usable articles of an RSS 2.0 feed, in feed order. Items without a
 * title, an https link on the partner's site, a body or a date are left out;
 * so are repeats of a guid.
 */
export function parsePartnerFeed(
  xml: string,
  source: PartnerSource,
  options: ParseOptions = {},
): PartnerArticle[] {
  const now = options.now ?? new Date();
  const maxItems = options.maxItems ?? 60;
  const site = new URL(source.siteUrl);
  const siteHost = site.hostname.toLowerCase().replace(/^www\./, "");
  const assetHosts = [siteHost, ...source.assetHosts.map((h) => h.toLowerCase())];

  const items = findAll(
    parseMarkup(xml, false),
    (element) => localName(element.name) === "item",
  );
  const seen = new Set<string>();
  const articles: PartnerArticle[] = [];

  for (const item of items) {
    if (articles.length >= maxItems) break;

    const link = resolveHttpUrl(fieldText(item, "link"), source.siteUrl);
    if (!link) continue;
    link.protocol = "https:";
    if (link.port || !hostMatches(link.hostname.toLowerCase(), siteHost)) {
      continue;
    }
    link.hash = "";
    const url = link.href;

    const guid = (fieldText(item, "guid") || url).slice(0, MAX_GUID);
    if (seen.has(guid)) continue;

    const title = truncate(htmlToText(fieldText(item, "title")), MAX_TITLE);
    if (!title) continue;

    const dateText = fieldText(item, "pubdate", "dc:date", "published", "updated");
    const timestamp = Date.parse(dateText);
    if (!Number.isFinite(timestamp)) continue;
    if (timestamp > now.getTime() + FUTURE_SLACK_MS) continue;
    const publishedAt = new Date(Math.min(timestamp, now.getTime()))
      .toISOString();

    const description = fieldText(item, "description");
    const body = fieldText(item, "content:encoded", "encoded") || description;
    const { blocks, leadImage } = htmlToBlocks(body, url, assetHosts);
    const markdown = joinBlocks(
      excerptBlocks(blocks, options.share ?? EXCERPT_SHARE),
    );
    if (!markdown) continue;

    // The description, else the body's first paragraph.
    const summary = htmlToText(description) ||
      (findAll(parseMarkup(body, true), (e) => e.name === "p")
        .map((p) => collapse(textContent(p)))
        .find((text) => text.length > 0) ?? "");

    seen.add(guid);
    articles.push({
      guid,
      url,
      title,
      summary: truncate(summary, MAX_SUMMARY),
      content: markdown,
      imageUrl: leadImage ?? itemImage(item, url, assetHosts),
      publishedAt,
    });
  }
  return articles;
}
