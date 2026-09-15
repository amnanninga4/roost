# Home screen — the short version

One page. What we decided, and what it costs. The build detail lives in
`docs/superpowers/specs/2026-09-15-home-screen-design.md`; you should not need to open it.

Decided 2026-09-15. Picture: `~/claude-reports/roost-home-mockup/roost-home-mockup.png`.

## What changes

**The app stops opening on the chore board.** Tab one becomes Home: the date, one plain sentence
("5 for you, 4 for Anne"), your own chores — checkable right there — the other person as a single
line, and four doors to Shopping, Meals, Projects, Wishlist.

**The board isn't going anywhere.** Both columns, side by side, exactly as they are now. It moves
one tap over, into the second half of the same tab. Not deleted, not buried in More.

**No new tab.** Still Home, Lists, More.

**Streaks leave the front door.** The Anne-vs-Wes card moves over with the board. It's a
scoreboard, and you already collapse it by default — the app has been telling us it's in the way.

**Empty rooms stay quiet.** A list with nothing in it shows its name and no count. No empty
cards, no "nothing here yet."

**Long lists fold.** More than six chores and it shows six plus a "3 more" line you can tap. It
remembers whether you left it open.

## What it costs

**You won't see both columns the moment you open the app.** That was a deliberate rule — both
lists always visible so neither of you can hide the other's from view. It's now one tap away
instead of immediate, and Home always tells you the other person's count.

That's the whole trade. If it turns out to be the wrong one, moving the board back to the front
is a small change, not a rebuild.

## What this is not

Not a dashboard. No metrics, no "your household at a glance," no greeting. The app names things;
it doesn't welcome you.

## Not in this round

The daily cap and bonus list. Movies & TV. Project deadlines. Any notification work — the server
still has no push key, so notifications do nothing regardless.

## Where it stands

Spec is written and open as PR #93. Next is the build plan, then it goes to Apple-Dev-3.
Nothing is being coded yet.
