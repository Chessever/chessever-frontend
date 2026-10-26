import { test } from "node:test";
import assert from "node:assert/strict";
import { readFile } from "node:fs/promises";
import {
  decodeEntities,
  htmlToMarkdown,
  type PartnerSource,
  parsePartnerFeed,
  youtubeId,
} from "./feed.ts";

const rookReview: PartnerSource = {
  id: "rookreview",
  siteUrl: "https://rookreview.com",
  assetHosts: ["rookreview.b-cdn.net"],
};
const now = new Date("2026-10-26T12:00:00Z");
const hosts = ["rookreview.com", "rookreview.b-cdn.net"];
const base = "https://rookreview.com/news/a";

function feed(items: string): string {
  return `<?xml version="1.0" encoding="UTF-8"?>
<rss version="2.0" xmlns:content="http://purl.org/rss/1.0/modules/content/">
<channel><title>RookReview</title>${items}</channel></rss>`;
}

function item(fields: Record<string, string>): string {
  const defaults: Record<string, string> = {
    title: "A title",
    link: "https://rookreview.com/news/a",
    pubDate: "Fri, 23 Oct 2026 18:39:00 +0000",
    description: "<![CDATA[The summary.]]>",
    "content:encoded": "<![CDATA[<p>The body.</p>]]>",
  };
  return `<item>${
    Object.entries({ ...defaults, ...fields })
      .filter(([, value]) => value !== "")
      .map(([name, value]) => `<${name}>${value}</${name}>`)
      .join("")
  }</item>`;
}

const markdown = (html: string) => htmlToMarkdown(html, base, hosts).markdown;

test("reads the real RookReview feed", async () => {
  const xml = await readFile(
    new URL("./testdata/rookreview_feed.xml", import.meta.url),
    "utf8",
  );
  const articles = parsePartnerFeed(xml, rookReview, { now });
  assert.equal(articles.length, 3);

  const [quote, table, links] = articles;
  assert.equal(
    quote.title,
    '"Hikaru is definitely not the best online Blitz player in the world. ' +
      'Magnus is still just far away best" — Olexandr Bortnyk',
  );
  assert.equal(
    quote.url,
    "https://rookreview.com/news/hikaru-is-definitely-not-the-best-online-blitz-player-in-the-world-magnus-is-still-just-far-away-best-olexandr-bortnyk",
  );
  assert.equal(quote.guid, quote.url);
  assert.equal(quote.publishedAt, "2026-10-24T18:29:00.000Z");
  assert.equal(
    quote.imageUrl,
    "https://rookreview.b-cdn.net/Players/Men/Nakamura%2C%20Hikaru/hikaru_nakamura-candidates-2026-08.jpeg",
  );
  assert.match(quote.summary, /^Olexandr Bortnyk shared his opinion/);
  // The cover left the body; the quote kept its paragraphs and speaker.
  assert.doesNotMatch(quote.content, /!\[/);
  assert.match(
    quote.content,
    /^> “Everyone thinks Hikaru is the best online Blitz player in the world\. I would say that I disagree with that\.\n>\n> He is in the top/m,
  );
  assert.match(quote.content, /\n>\n> \*Olexandr Bortnyk — Ukrainian GM\*\n\n/);
  assert.match(
    quote.content,
    /Hikaru \[reached\]\(https:\/\/rookreview\.com\/news\/3500-in-blitz-hikaru-nakamura-breaks-chesscom-record\) the record/,
  );
  assert.match(quote.content, /\n\nCredit: Yoav Nisenbaum \/ FIDE$/);

  assert.equal(table.title, "Hans Niemann Wins Freestyle Friday with 9 Points on October 23");
  assert.match(
    table.content,
    /\n\n\| Place \| Player \| Score \| TB \| Prize \|\n\| --- \| --- \| --- \| --- \| --- \|\n\| 1\. \| \u{1F1FA}\u{1F1F8} GM Hans Moke Niemann \| 9 \| 73\.5 \| \$400 \|\n/u,
  );
  assert.equal(table.content.match(/^\| /gm)?.length, 7);

  assert.equal(links.title, "Lichess Ends Its Boycott of US Chess");
  assert.equal(links.content.split("\n\n").length, 6);
});

test("paragraphs never leak markup or start a block by accident", () => {
  assert.equal(
    markdown("<p>Use *stars*, _scores_, [brackets] & <b>bold</b> &amp;amp; ok</p>"),
    "Use \\*stars\\*, \\_scores\\_, \\[brackets\\] & **bold** \\&amp; ok",
  );
  assert.equal(markdown("<p>1. e4 e5</p><p># not a heading</p><p>- not a list</p>"),
    "1\\. e4 e5\n\n\\# not a heading\n\n\\- not a list");
  assert.equal(markdown("<p>one<br>two<br/></p>"), "one\\\ntwo");
  assert.equal(markdown("<p>  spaced \n\n text  </p><p> </p><p><b> </b></p>"), "spaced text");
  assert.equal(markdown("<div>loose text<p>para</p>tail</div>"), "loose text\n\npara\n\ntail");
  assert.equal(markdown("<p>unclosed<p>next"), "unclosed\n\nnext");
});

test("drops scripts, styles, forms and foreign embeds", () => {
  assert.equal(
    markdown(
      '<p>a</p><script>alert(1)</script><style>p{}</style><form><input value="x"></form>' +
        '<iframe src="https://evil.example/x"></iframe><p onclick="x()">b</p>',
    ),
    "a\n\nb",
  );
});

test("links keep only http(s) targets and resolve relative ones", () => {
  assert.equal(
    markdown('<p><a href="/news/b">rel</a> <a href="javascript:alert(1)">js</a> <a href="https://x.com/a b(c)">sp</a></p>'),
    "[rel](https://rookreview.com/news/b) js [sp](https://x.com/a%20b%28c%29)",
  );
  assert.equal(markdown('<p><a href="https://x.com"> padded </a>end</p>'), "[padded](https://x.com/) end");
});

test("pictures come only from the partner's hosts; the opening one is the cover", () => {
  const result = htmlToMarkdown(
    '<p><img src="https://rookreview.b-cdn.net/a b.jpg" alt="Cover [1]"></p><p>Text</p>' +
      '<p><img src="https://tracker.example/p.gif"><img src="/inline.png" alt="x"></p>',
    base,
    hosts,
  );
  assert.equal(result.leadImage, "https://rookreview.b-cdn.net/a%20b.jpg");
  assert.equal(result.markdown, "Text\n\n![x](https://rookreview.com/inline.png)");

  const linked = htmlToMarkdown(
    '<a href="https://rookreview.com/x"><img src="https://rookreview.b-cdn.net/c.jpg"></a><p>t</p>',
    base,
    hosts,
  );
  assert.equal(linked.leadImage, "https://rookreview.b-cdn.net/c.jpg");
  assert.equal(htmlToMarkdown("<p>t</p><p><img src='https://rookreview.b-cdn.net/c.jpg'></p>", base, hosts).leadImage, null);
});

test("quotes, headings, lists, tables and code", () => {
  assert.equal(
    markdown("<blockquote><p>one</p><p>two</p><footer>Speaker — GM</footer></blockquote>"),
    "> one\n>\n> two\n>\n> *Speaker — GM*",
  );
  assert.equal(markdown("<h1>Big</h1><h3>Mid</h3><h5>Small</h5>"), "## Big\n\n### Mid\n\n#### Small");
  assert.equal(
    markdown("<ul><li>a<ul><li>nested</li></ul></li><li>1. b</li></ul><ol start='3'><li>c<li>d</ol>"),
    "- a\n- nested\n- 1\\. b\n\n3. c\n4. d",
  );
  assert.equal(
    markdown("<table><tr><td>a|b</td><td>c</td></tr><tr><td>d</td></tr></table>"),
    "| a\\|b | c |\n| --- | --- |\n| d |  |",
  );
  assert.equal(markdown("<table><tr><td> </td></tr></table><p>x</p>"), "x");
  assert.equal(markdown("<pre>a\n  b ``` c</pre>"), "````\na\n  b ``` c\n````");
  assert.equal(markdown("<p>run <code>e4`e5</code></p>"), "run ``e4`e5``");
});

test("YouTube embeds become the apps' video marker", () => {
  assert.equal(
    markdown('<p>a</p><iframe src="https://www.youtube.com/embed/dQw4w9WgXcQ?si=1"></iframe>'),
    "a\n\n<!-- news-youtube: dQw4w9WgXcQ -->",
  );
  assert.equal(youtubeId("https://youtu.be/dQw4w9WgXcQ"), "dQw4w9WgXcQ");
  assert.equal(youtubeId("//www.youtube-nocookie.com/embed/dQw4w9WgXcQ"), "dQw4w9WgXcQ");
  assert.equal(youtubeId("https://www.youtube.com/watch?v=dQw4w9WgXcQ"), "dQw4w9WgXcQ");
  assert.equal(youtubeId("https://www.youtube.com/watch?v=short"), null);
  assert.equal(youtubeId("https://evil.example/embed/dQw4w9WgXcQ"), null);
});

test("entities decode once, safely", () => {
  assert.equal(decodeEntities("&quot;a&quot; &amp; &#8217;&#x2019; &bogus; &#0; &#xD800;"), "\"a\" & ’’ &bogus; � �");
});

test("keeps only items linking https into the partner's own site", () => {
  const articles = parsePartnerFeed(
    feed(
      item({ link: "https://evil.example/news/a" }) +
        item({ link: "https://rookreview.com.evil.example/a" }) +
        item({ link: "javascript:alert(1)" }) +
        item({ link: "http://www.rookreview.com/news/b#top", title: "Upgraded" }) +
        item({ link: "https://rookreview.com:8443/news/c" }),
    ),
    rookReview,
    { now },
  );
  assert.deepEqual(articles.map((a) => a.url), ["https://www.rookreview.com/news/b"]);
});

test("skips items without a title, body or date, and repeated guids", () => {
  const articles = parsePartnerFeed(
    feed(
      item({ title: "" }) +
        item({ title: "No body", "content:encoded": "<![CDATA[<script>x</script>]]>", description: "" }) +
        item({ title: "No date", pubDate: "" }) +
        item({ title: "Bad date", pubDate: "yesterday-ish" }) +
        item({ title: "Far future", pubDate: "Fri, 23 Oct 2099 18:39:00 +0000" }) +
        item({ title: "Kept", guid: "g1" }) +
        item({ title: "Repeat", guid: "g1" }),
    ),
    rookReview,
    { now },
  );
  assert.deepEqual(articles.map((a) => a.title), ["Kept"]);
  assert.equal(articles[0].guid, "g1");
});

test("a date slightly ahead is clamped to now; HTML in titles is text", () => {
  const [article] = parsePartnerFeed(
    feed(item({ title: "&lt;b&gt;Bold&lt;/b&gt; &amp; co", pubDate: "Mon, 26 Oct 2026 13:00:00 +0000" })),
    rookReview,
    { now },
  );
  assert.equal(article.publishedAt, now.toISOString());
  assert.equal(article.title, "Bold & co");
});

test("summary falls back to the first paragraph; body to the description", () => {
  const [fromBody] = parsePartnerFeed(
    feed(item({ description: "", "content:encoded": "<![CDATA[<p></p><p>First &amp; <b>real</b> one.</p><p>Second.</p>]]>" })),
    rookReview,
    { now },
  );
  assert.equal(fromBody.summary, "First & real one.");
  assert.equal(fromBody.content, "First & **real** one.\n\nSecond.");

  const [fromDescription] = parsePartnerFeed(
    feed(item({ "content:encoded": "", description: "<![CDATA[<p>Only <i>this</i>.</p>]]>" })),
    rookReview,
    { now },
  );
  assert.equal(fromDescription.content, "Only *this*.");
  assert.equal(fromDescription.summary, "Only this.");
});

test("an enclosure is the cover when the body opens without one", () => {
  const [article] = parsePartnerFeed(
    feed(
      item({ "content:encoded": "<![CDATA[<p>Body</p>]]>" }).replace(
        "</item>",
        '<enclosure url="https://rookreview.b-cdn.net/e.jpg" type="image/jpeg" length="1"/></item>',
      ),
    ),
    rookReview,
    { now },
  );
  assert.equal(article.imageUrl, "https://rookreview.b-cdn.net/e.jpg");

  const [foreign] = parsePartnerFeed(
    feed(item({}).replace("</item>", '<enclosure url="https://cdn.example/e.jpg" type="image/jpeg"/></item>')),
    rookReview,
    { now },
  );
  assert.equal(foreign.imageUrl, null);
});

test("long summaries are cut on a word", () => {
  const [article] = parsePartnerFeed(
    feed(item({ description: `<![CDATA[${"word ".repeat(300)}]]>` })),
    rookReview,
    { now },
  );
  assert.ok(article.summary.length <= 600);
  assert.match(article.summary, /word…$/);
});
