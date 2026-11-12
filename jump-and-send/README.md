# Jump and Send — v3.2

**Status: in daily use; coverage varies by app — read the notes. Telegram was device-tested on November 12, 2026, and 3.2 fixes the chat list failure that test found.**

One jump key for browsing and chat. SandFly+J jumps past toolbars to the content in Chrome and YouTube; in Muse, Gemini, ChatGPT, Google Messages, and Facebook Messenger it jumps between the message box and the most recent message, and SandFly+Enter sends. On the Messenger home screen, J jumps straight to your most recent chat. Google Messages on a tablet (paired web view) gets a three-stop cycle. Send does nothing in Chrome or YouTube.

Telegram works the way the Thunderbird script does: focus only lands on real content and only moves when you move it on purpose.

- SandFly+J jumps between the message box and the most recent message. With no chat open, it jumps into the topics list or the chat list — on the chat list it lands on the first chat, wherever focus started. The chat list's own search box is not the message box: J steps past it into the list, and Send never treats a search as a draft (fixed in 3.2; in 3.1 the search box trapped J and the arrows).
- Plain Up and Down step within the list you are in — messages, topics, or chats — and nowhere else. Empty rows, reply quotes, banners, and floating buttons are never stops. At either end the script says First or Last instead of letting focus wander off.
- The arrows are bound only while Telegram is in front and are given back the moment you leave it, so every other app keeps SandFly's normal arrow behaviour. SandFly+N and SandFly+P step too.
- Enter opens the focused chat or topic (SandFly's own keymap does that). SandFly+Enter sends, and only ever clicks the button named exactly Send; with an empty box it says Nothing to send.

Known notes, honestly:

- In Google Messages' conversation *list* (before you open a chat) there is no message box on that screen, so J reports that — open a conversation and J works as described. In the paired tablet view, J on that same screen drops you into the conversation list on the first conversation instead (new in 3.1, from the November 11, 2026 screen tree).
- Per-app send coverage is still being confirmed app by app; where script send does not fire, plain Enter is the working send.
- Telegram: which of the stacked lists J lands on is settled — rows decide, and on the chat list J lands on the first real chat row (the screen also carries a stories strip and a search box, and neither is ever a stop). Still open: whether focus scrolls to rows that start off screen.

Download `chat-jump-send.lua` and import it into SandFly.
