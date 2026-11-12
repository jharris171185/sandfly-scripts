# Jump and Send — v3.1

**Status: in daily use; coverage varies by app — read the notes. The Telegram support is new in 3.0 and untested.**

One jump key for browsing and chat. SandFly+J jumps past toolbars to the content in Chrome and YouTube; in Muse, Gemini, ChatGPT, Google Messages, and Facebook Messenger it jumps between the message box and the most recent message, and SandFly+Enter sends. On the Messenger home screen, J jumps straight to your most recent chat. Google Messages on a tablet (paired web view) gets a three-stop cycle. Send does nothing in Chrome or YouTube.

Telegram works the way the Thunderbird script does: focus only lands on real content and only moves when you move it on purpose.

- SandFly+J jumps between the message box and the most recent message. With no chat open, it jumps into the topics list or the chat list.
- Plain Up and Down step within the list you are in — messages, topics, or chats — and nowhere else. Empty rows, reply quotes, banners, and floating buttons are never stops. At either end the script says First or Last instead of letting focus wander off.
- The arrows are bound only while Telegram is in front and are given back the moment you leave it, so every other app keeps SandFly's normal arrow behaviour. SandFly+N and SandFly+P step too.
- Enter opens the focused chat or topic (SandFly's own keymap does that). SandFly+Enter sends, and only ever clicks the button named exactly Send; with an empty box it says Nothing to send.

Known notes, honestly:

- In Google Messages' conversation *list* (before you open a chat) there is no message box on that screen, so J reports that — open a conversation and J works as described. In the paired tablet view, J on that same screen drops you into the conversation list on the first conversation instead (new in 3.1, from the November 11, 2026 screen tree).
- Per-app send coverage is still being confirmed app by app; where script send does not fire, plain Enter is the working send.
- Telegram 3.0 is untested so far: whether focus scrolls to rows that start off screen, and which of Telegram's stacked chat lists J lands on before a chat is opened, are open questions.

Download `chat-jump-send.lua` and import it into SandFly.
