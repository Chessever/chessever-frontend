# Live Game Streaming: Scalability Brief

> **For:** Product Manager
> **Date:** December 2024
> **Status:** Short-term fix deployed, long-term action required

---

## The Problem We Fixed

**What users experienced:**
- Chess boards not loading immediately when browsing tournaments
- 2-5 second delays when switching between grid/list views
- Occasional "connection error" messages during busy tournaments

**Root cause:**
Our app was opening too many connections to the server - one for each game displayed on screen. Supabase (our backend) has limits on how many connections can be opened at once.

---

## The Short-Term Fix (Current Release)

**What we did:**
Instead of opening 1 connection per game, we now batch games together. Think of it like carpooling - instead of 50 people driving 50 cars, we put 100 people in 1 bus.

**Result:**
- Viewing 50 games: 1 connection (was 50)
- Viewing 500 games: 5 connections (was 500)
- No more delays or errors

---

## Current Capacity (What We Can Handle Now)

| Scenario | Supported? | Notes |
|----------|------------|-------|
| 500 users watching 100+ live games | Yes | No extra cost |
| 1,000 users watching 500 live games | Yes | ~$5/month extra |
| 5,000 users watching 1,000 live games | Yes | ~$45/month extra |
| 10,000+ users simultaneously | Yes | ~$95/month extra |

**The math is simple:** Each online user = 1 connection. Number of games doesn't matter anymore.

---

## The Spending Cap Issue

### What is the spending cap?
Supabase has a safety feature that stops your app when you hit certain limits. This prevents surprise bills but also means your app goes offline.

### Why we need to disable it
Our Pro plan includes **500 concurrent connections** for free. If we have a popular tournament with 600 users watching at the same time:

- **With spending cap ON:** App stops working for user #501 onwards
- **With spending cap OFF:** App works for everyone, we pay ~$1 extra that month

### Cost breakdown
| Extra concurrent users | Extra monthly cost |
|------------------------|-------------------|
| 500 (first 500 free) | $0 |
| +1,000 users | +$10 |
| +5,000 users | +$50 |
| +10,000 users | +$100 |

### Recommendation
**Disable the spending cap** before any major tournament. The cost is predictable and low ($10 per 1,000 extra users), and it prevents the app from going offline during peak usage.

---

## Action Items

### Immediate (Before Next Major Tournament)
- [ ] Disable Supabase spending cap in dashboard
- [ ] Set up billing alerts at $50 and $100 thresholds

### Future Release (If We Grow Beyond 5,000 Concurrent Users)
We have a more advanced solution documented ("Option B") that reduces server load significantly. This should be implemented when:
- We consistently see 5,000+ concurrent users
- We notice database performance issues during peak times

---

## Summary

| Aspect | Before Fix | After Fix |
|--------|------------|-----------|
| Connections per 50 games | 50 | 1 |
| Max concurrent users | ~100 (errors after) | 500 free, unlimited with small fee |
| User experience | Delays, errors | Instant loading |
| Monthly cost impact | N/A | $10 per 1,000 users over 500 |

**Bottom line:** The fix is deployed. To handle growth beyond 500 concurrent users, we just need to disable the spending cap. Cost is minimal and predictable.

---

*Technical details: See `REALTIME_CHANNEL_FIX_OPTION_A.md` and `REALTIME_OPTION_B_SCALABILITY.md` in the project root.*
