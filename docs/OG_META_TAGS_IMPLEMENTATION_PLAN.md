# OG Meta Tags Implementation Plan for ChessEver Game URLs

## Overview

This document provides a comprehensive implementation plan for adding Open Graph (OG) meta tags to ChessEver game URLs (`https://chessever.com/games/<game-id>/`) to enable rich link previews when shared on social media platforms (Twitter/X, Facebook, WhatsApp, Telegram, Discord, iMessage, etc.).

---

## 1. Current State Analysis

### URL Structure
- **Game URL Format:** `https://chessever.com/games/{gameId}`
- **Example:** `https://chessever.com/games/abc123xyz`

### Data Available in `games` Table
| Column | Type | Description |
|--------|------|-------------|
| `id` | text | Primary key - game identifier |
| `tour_id` | text | Foreign key to `tours` table |
| `tour_slug` | text | URL-friendly tournament name |
| `round_id` | text | Foreign key to `rounds` table |
| `round_slug` | text | URL-friendly round name |
| `fen` | text | Current board position (FEN notation) |
| `players` | jsonb | Array of 2 player objects |
| `status` | text | Game result: `*`, `1-0`, `0-1`, `1/2-1/2` |
| `board_nr` | smallint | Board number in tournament |
| `last_move` | text | Last move in SAN notation |
| `pgn` | text | Full game notation (PGN) |

### Player Object Structure (inside `players` JSONB)
```json
{
  "name": "Magnus Carlsen",
  "title": "GM",
  "rating": 2830,
  "fideId": 1503014,
  "fed": "NOR",
  "clock": 360000,
  "team": ""
}
```

### Related Tables
- **`tours`**: Tournament info (`id`, `name`, `slug`, `info`, `image`, `dates`)
- **`rounds`**: Round info (`id`, `slug`, `name`, `starts_at`)

---

## 2. Required OG Meta Tags

### Essential Meta Tags
```html
<!-- Primary Meta Tags -->
<meta name="title" content="{title}">
<meta name="description" content="{description}">

<!-- Open Graph / Facebook -->
<meta property="og:type" content="website">
<meta property="og:url" content="https://chessever.com/games/{gameId}">
<meta property="og:title" content="{title}">
<meta property="og:description" content="{description}">
<meta property="og:image" content="{image_url}">
<meta property="og:image:width" content="1200">
<meta property="og:image:height" content="630">
<meta property="og:site_name" content="ChessEver">

<!-- Twitter -->
<meta property="twitter:card" content="summary_large_image">
<meta property="twitter:url" content="https://chessever.com/games/{gameId}">
<meta property="twitter:title" content="{title}">
<meta property="twitter:description" content="{description}">
<meta property="twitter:image" content="{image_url}">
```

---

## 3. Content Strategy for Meta Tags

### Title Format
```
{WhiteTitle} {WhiteName} ({WhiteElo}) vs {BlackTitle} {BlackName} ({BlackElo}) | {Result}
```

**Examples:**
- `GM Magnus Carlsen (2830) vs GM Fabiano Caruana (2805) | 1-0`
- `GM Hikaru Nakamura (2789) vs IM John Doe (2450) | ½-½`
- `GM Anish Giri (2760) vs GM Wesley So (2770) | Live`

**Edge Cases:**
- No title: Skip title prefix (e.g., `John Smith (2100)`)
- No rating: Use "Unr" (e.g., `FM John Smith (Unr)`)
- Game ongoing: Use "Live" or "In Progress" instead of result

### Description Format
```
{TournamentName} - {RoundName} | Board {BoardNr}
{GameStatusDescription}
Watch and analyze on ChessEver
```

**Examples:**
- `World Chess Championship 2024 - Round 7 | Board 1
  White wins in 45 moves. Watch and analyze on ChessEver`

- `Tata Steel Chess 2024 - Round 3 | Board 5
  Draw by agreement. Watch and analyze on ChessEver`

- `Norway Chess 2024 - Round 2 | Board 3
  Game in progress. Watch live on ChessEver`

**Game Status Descriptions:**
| Status | Description |
|--------|-------------|
| `1-0` | "White wins" (optionally add move count from PGN) |
| `0-1` | "Black wins" (optionally add move count from PGN) |
| `1/2-1/2` | "Draw" |
| `*` | "Game in progress" or "Live" |

---

## 4. OG Image Generation

### Option A: Dynamic Server-Side Image Generation (Recommended)

Create an Edge Function or serverless function that generates preview images dynamically.

**Image Specifications:**
- **Dimensions:** 1200x630 pixels (optimal for all platforms)
- **Format:** PNG or JPEG
- **URL Pattern:** `https://chessever.com/api/og-image/{gameId}`

**Image Content Layout:**
```
┌──────────────────────────────────────────────────────────────┐
│  ChessEver Logo (top-left)                                   │
│                                                              │
│  ┌─────────────┐   GM Magnus Carlsen (2830) 🇳🇴             │
│  │             │   vs                                        │
│  │  Chess      │   GM Fabiano Caruana (2805) 🇺🇸             │
│  │  Board      │                                             │
│  │  Position   │   1-0  ●                                   │
│  │             │                                             │
│  └─────────────┘   World Championship 2024                   │
│                    Round 7 • Board 1                         │
│                                                              │
│  chessever.com                               (bottom-right)  │
└──────────────────────────────────────────────────────────────┘
```

**Required Elements:**
1. ChessEver branding (logo)
2. Chessboard showing current position (from FEN)
3. Player names with titles, ratings, and country flags
4. Game result/status indicator
5. Tournament and round information
6. ChessEver URL watermark

### Option B: Pre-Generated Static Images

Generate and store images in Supabase Storage when games are created/updated.

**Pros:** Faster loading, no runtime computation
**Cons:** Storage costs, needs update mechanism

### Option C: Third-Party OG Image Service

Use services like:
- Vercel OG (`@vercel/og`)
- Cloudinary
- imgix

---

## 5. Backend Implementation

### 5.1 Supabase Edge Function for OG Image

Create a new Edge Function: `supabase/functions/og-image/index.ts`

```typescript
// supabase/functions/og-image/index.ts
import { serve } from 'https://deno.land/std@0.168.0/http/server.ts'
import { createClient } from 'https://esm.sh/@supabase/supabase-js@2'

// You'll need a library like Satori + Resvg for image generation
// or use canvas-based approach

serve(async (req) => {
  const url = new URL(req.url)
  const gameId = url.pathname.split('/').pop()

  // Fetch game data
  const supabase = createClient(
    Deno.env.get('SUPABASE_URL')!,
    Deno.env.get('SUPABASE_ANON_KEY')!
  )

  const { data: game, error } = await supabase
    .from('games')
    .select(`
      id,
      fen,
      status,
      board_nr,
      players,
      tour_slug,
      round_slug,
      tours!games_tour_id_fkey (
        name,
        image
      ),
      rounds!games_round_id_fkey (
        name
      )
    `)
    .eq('id', gameId)
    .single()

  if (error || !game) {
    // Return default ChessEver OG image
    return new Response(/* default image */)
  }

  // Generate image with game data
  const image = await generateOgImage(game)

  return new Response(image, {
    headers: {
      'Content-Type': 'image/png',
      'Cache-Control': 'public, max-age=3600', // Cache for 1 hour
    },
  })
})
```

### 5.2 Database Query for OG Data

**SQL Query to fetch all required OG data:**

```sql
SELECT
  g.id,
  g.fen,
  g.status,
  g.board_nr,
  g.players,
  g.pgn,
  g.tour_slug,
  g.round_slug,
  t.name as tournament_name,
  t.image as tournament_image,
  r.name as round_name
FROM games g
LEFT JOIN tours t ON g.tour_id = t.id
LEFT JOIN rounds r ON g.round_id = r.id
WHERE g.id = $1
```

**Supabase JavaScript Query:**

```typescript
const { data, error } = await supabase
  .from('games')
  .select(`
    id,
    fen,
    status,
    board_nr,
    players,
    pgn,
    tour_slug,
    round_slug,
    tours!games_tour_id_fkey (
      name,
      image
    ),
    rounds!games_round_id_fkey (
      name
    )
  `)
  .eq('id', gameId)
  .single()
```

### 5.3 Edge Function for HTML Meta Tags

Create: `supabase/functions/game-meta/index.ts`

This function returns HTML with proper meta tags for crawlers (bots that don't execute JavaScript).

```typescript
serve(async (req) => {
  const url = new URL(req.url)
  const gameId = url.pathname.split('/').pop()

  const game = await fetchGameData(gameId)

  if (!game) {
    return new Response('Not found', { status: 404 })
  }

  const { title, description, imageUrl } = formatOgData(game)

  const html = `
<!DOCTYPE html>
<html>
<head>
  <meta charset="UTF-8">
  <title>${title}</title>
  <meta name="description" content="${description}">

  <!-- Open Graph -->
  <meta property="og:type" content="website">
  <meta property="og:url" content="https://chessever.com/games/${gameId}">
  <meta property="og:title" content="${title}">
  <meta property="og:description" content="${description}">
  <meta property="og:image" content="${imageUrl}">
  <meta property="og:image:width" content="1200">
  <meta property="og:image:height" content="630">
  <meta property="og:site_name" content="ChessEver">

  <!-- Twitter -->
  <meta name="twitter:card" content="summary_large_image">
  <meta name="twitter:title" content="${title}">
  <meta name="twitter:description" content="${description}">
  <meta name="twitter:image" content="${imageUrl}">

  <!-- Redirect to app -->
  <meta http-equiv="refresh" content="0;url=chessever://games/${gameId}">
  <script>
    // Redirect logic for web vs app
    window.location.href = 'https://chessever.com/games/${gameId}';
  </script>
</head>
<body>
  <p>Redirecting to ChessEver...</p>
</body>
</html>
  `

  return new Response(html, {
    headers: { 'Content-Type': 'text/html' },
  })
})
```

---

## 6. Web Server Configuration

### Option A: Vercel/Next.js (If using web app)

Create dynamic route: `app/games/[gameId]/page.tsx`

```typescript
// app/games/[gameId]/page.tsx
import { Metadata } from 'next'
import { createClient } from '@supabase/supabase-js'

type Props = {
  params: { gameId: string }
}

export async function generateMetadata({ params }: Props): Promise<Metadata> {
  const game = await fetchGame(params.gameId)

  if (!game) {
    return { title: 'Game Not Found | ChessEver' }
  }

  const title = formatTitle(game)
  const description = formatDescription(game)
  const imageUrl = `https://chessever.com/api/og-image/${params.gameId}`

  return {
    title,
    description,
    openGraph: {
      title,
      description,
      url: `https://chessever.com/games/${params.gameId}`,
      siteName: 'ChessEver',
      images: [
        {
          url: imageUrl,
          width: 1200,
          height: 630,
          alt: title,
        },
      ],
      type: 'website',
    },
    twitter: {
      card: 'summary_large_image',
      title,
      description,
      images: [imageUrl],
    },
  }
}
```

### Option B: Cloudflare Workers

```typescript
// workers/og-handler.ts
export default {
  async fetch(request: Request): Promise<Response> {
    const url = new URL(request.url)

    // Check if request is from a bot/crawler
    const userAgent = request.headers.get('User-Agent') || ''
    const isBot = /bot|crawl|spider|facebook|twitter|telegram|whatsapp|discord|slack/i.test(userAgent)

    if (isBot && url.pathname.startsWith('/games/')) {
      const gameId = url.pathname.split('/')[2]
      return await generateBotResponse(gameId)
    }

    // Regular users: redirect to app or web app
    return Response.redirect('https://app.chessever.com' + url.pathname)
  }
}
```

---

## 7. Chessboard Image Generation

### Using Chess Libraries

For generating the board position image from FEN:

**Option 1: Server-Side with Node.js/Deno**
```typescript
import { Chess } from 'chess.js'
import { Chessground } from 'chessground' // or similar

function generateBoardSvg(fen: string): string {
  // Parse FEN and generate SVG board
  const chess = new Chess(fen)
  // ... generate board visualization
  return svgString
}
```

**Option 2: Use chessboard rendering service**
- `https://chessboardimage.com/{fen}.png`
- `https://lichess1.org/export/fen.gif?fen={encodedFen}`
- Self-hosted solution using canvas

**Option 3: Pre-render with Puppeteer/Playwright**
```typescript
// Render a headless browser with chessboard component
const browser = await puppeteer.launch()
const page = await browser.newPage()
await page.setContent(chessboardHtml)
const screenshot = await page.screenshot({ type: 'png' })
```

---

## 8. Helper Functions

### Format Title
```typescript
function formatTitle(game: Game): string {
  const white = game.players[0]
  const black = game.players[1]

  const whiteName = formatPlayerName(white)
  const blackName = formatPlayerName(black)
  const result = formatResult(game.status)

  return `${whiteName} vs ${blackName} | ${result}`
}

function formatPlayerName(player: Player): string {
  const title = player.title ? `${player.title} ` : ''
  const rating = player.rating > 0 ? `(${player.rating})` : '(Unr)'
  return `${title}${player.name} ${rating}`
}

function formatResult(status: string): string {
  switch (status) {
    case '1-0': return '1-0'
    case '0-1': return '0-1'
    case '1/2-1/2': return '½-½'
    case '*': return 'Live'
    default: return ''
  }
}
```

### Format Description
```typescript
function formatDescription(game: Game): string {
  const tournament = game.tours?.name || formatSlug(game.tour_slug)
  const round = game.rounds?.name || formatSlug(game.round_slug)
  const board = game.board_nr ? `Board ${game.board_nr}` : ''

  let statusText = ''
  switch (game.status) {
    case '1-0': statusText = 'White wins'; break
    case '0-1': statusText = 'Black wins'; break
    case '1/2-1/2': statusText = 'Draw'; break
    case '*': statusText = 'Game in progress'; break
  }

  return `${tournament} - ${round}${board ? ' | ' + board : ''}\n${statusText}. Watch and analyze on ChessEver`
}

function formatSlug(slug: string): string {
  return slug
    .split('-')
    .map(word => word.charAt(0).toUpperCase() + word.slice(1))
    .join(' ')
}
```

---

## 9. Caching Strategy

### Redis/KV Cache
```typescript
const CACHE_TTL = {
  LIVE_GAME: 60,        // 1 minute for ongoing games
  FINISHED_GAME: 86400, // 24 hours for finished games
  OG_IMAGE: 3600,       // 1 hour for images
}

async function getCachedOgData(gameId: string) {
  const cached = await kv.get(`og:${gameId}`)
  if (cached) return cached

  const data = await fetchAndFormatOgData(gameId)
  const ttl = data.status === '*' ? CACHE_TTL.LIVE_GAME : CACHE_TTL.FINISHED_GAME

  await kv.set(`og:${gameId}`, data, { ex: ttl })
  return data
}
```

### HTTP Cache Headers
```typescript
const cacheControl = game.status === '*'
  ? 'public, max-age=60, s-maxage=60'           // Live games: 1 min
  : 'public, max-age=86400, s-maxage=86400'     // Finished: 24 hours
```

---

## 10. Implementation Checklist

### Phase 1: Backend Setup
- [ ] Create Supabase Edge Function for OG data (`/functions/game-meta`)
- [ ] Create database query with proper joins (games + tours + rounds)
- [ ] Implement helper functions (formatTitle, formatDescription, etc.)
- [ ] Add caching layer

### Phase 2: OG Image Generation
- [ ] Design OG image template (1200x630)
- [ ] Set up image generation service (Vercel OG, Satori, or canvas)
- [ ] Create chess board rendering from FEN
- [ ] Add player info, flags, and branding to image
- [ ] Create Edge Function for dynamic image generation (`/api/og-image/{gameId}`)

### Phase 3: Web Server/Routing
- [ ] Configure web server to handle `/games/{gameId}` routes
- [ ] Detect bot/crawler user agents
- [ ] Return HTML with meta tags for bots
- [ ] Redirect regular users to app/web app

### Phase 4: Testing & Validation
- [ ] Test with Facebook Sharing Debugger: https://developers.facebook.com/tools/debug/
- [ ] Test with Twitter Card Validator: https://cards-dev.twitter.com/validator
- [ ] Test with LinkedIn Post Inspector: https://www.linkedin.com/post-inspector/
- [ ] Test on WhatsApp, Telegram, Discord, iMessage
- [ ] Verify image dimensions and quality

### Phase 5: Monitoring & Optimization
- [ ] Add analytics for shared links
- [ ] Monitor image generation performance
- [ ] Set up error alerting
- [ ] Optimize caching based on usage patterns

---

## 11. Example Outputs

### Example 1: Live Game
**URL:** `https://chessever.com/games/wcc2024-r7-g1`

**Meta Tags:**
```html
<meta property="og:title" content="GM Magnus Carlsen (2830) vs GM Fabiano Caruana (2805) | Live">
<meta property="og:description" content="World Chess Championship 2024 - Round 7 | Board 1
Game in progress. Watch live on ChessEver">
<meta property="og:image" content="https://chessever.com/api/og-image/wcc2024-r7-g1">
```

### Example 2: Finished Game
**URL:** `https://chessever.com/games/tata2024-r3-g5`

**Meta Tags:**
```html
<meta property="og:title" content="GM Anish Giri (2760) vs GM Wesley So (2770) | ½-½">
<meta property="og:description" content="Tata Steel Chess 2024 - Round 3 | Board 5
Draw in 42 moves. Watch and analyze on ChessEver">
<meta property="og:image" content="https://chessever.com/api/og-image/tata2024-r3-g5">
```

---

## 12. Architecture Diagram

```
┌─────────────────────────────────────────────────────────────────────┐
│                        User Shares Game Link                         │
│                 https://chessever.com/games/{gameId}                │
└─────────────────────────────────────────────────────────────────────┘
                                    │
                                    ▼
┌─────────────────────────────────────────────────────────────────────┐
│                     Web Server / Edge Function                       │
│                    (Cloudflare Workers / Vercel)                    │
└─────────────────────────────────────────────────────────────────────┘
                                    │
                    ┌───────────────┴───────────────┐
                    ▼                               ▼
            ┌───────────────┐               ┌───────────────┐
            │   Bot/Crawler │               │  Regular User │
            │   (Facebook,  │               │   (Browser)   │
            │   Twitter...)  │               │               │
            └───────────────┘               └───────────────┘
                    │                               │
                    ▼                               ▼
┌─────────────────────────────────┐    ┌─────────────────────────────┐
│       Return HTML with          │    │     Redirect to App or      │
│       OG Meta Tags              │    │     Web Application         │
└─────────────────────────────────┘    └─────────────────────────────┘
                    │
                    ▼
┌─────────────────────────────────────────────────────────────────────┐
│                         Supabase Database                           │
│   ┌─────────┐    ┌─────────┐    ┌─────────┐                        │
│   │  games  │◄───│  tours  │    │ rounds  │                        │
│   │ (main)  │    │ (join)  │    │ (join)  │                        │
│   └─────────┘    └─────────┘    └─────────┘                        │
└─────────────────────────────────────────────────────────────────────┘
                    │
                    ▼
┌─────────────────────────────────────────────────────────────────────┐
│                    OG Image Generation Service                       │
│   ┌─────────────────────────────────────────────────────────────┐   │
│   │  • Parse FEN → Generate chessboard image                    │   │
│   │  • Add player names, ratings, flags                         │   │
│   │  • Add tournament/round info                                │   │
│   │  • Add ChessEver branding                                   │   │
│   │  • Return 1200x630 PNG                                      │   │
│   └─────────────────────────────────────────────────────────────┘   │
└─────────────────────────────────────────────────────────────────────┘
```

---

## 13. Recommended Tech Stack

| Component | Recommendation | Alternative |
|-----------|---------------|-------------|
| Web Server | Cloudflare Workers | Vercel Edge Functions |
| OG Image | Vercel OG (@vercel/og) | Satori + Resvg |
| Board Rendering | chess.js + custom SVG | Lichess API |
| Caching | Cloudflare KV | Redis |
| Database | Supabase (already in use) | - |

---

## 14. Cost Considerations

| Service | Free Tier | Estimated Cost |
|---------|-----------|----------------|
| Cloudflare Workers | 100K req/day | ~$5/mo for 10M req |
| Vercel OG | Included with Vercel | - |
| Supabase | 500MB database | Already covered |
| Image CDN | Varies | ~$10-20/mo |

---

## 15. Security Considerations

1. **Rate Limiting:** Limit OG image generation requests
2. **Input Validation:** Sanitize gameId parameter
3. **Cache Poisoning:** Validate cache keys
4. **XSS Prevention:** Escape all user-generated content in HTML

---

## Summary

This implementation will enable rich, dynamic link previews for shared ChessEver game links, showing:
- Player names with titles, ratings, and country flags
- Current board position
- Game result or live status
- Tournament and round information
- ChessEver branding

The solution uses Supabase Edge Functions for server-side rendering and dynamic OG image generation, with proper caching for performance.
