## 01/17/2025

- Unfortunately, the request-completer pattern does not work with the HTTP requests,
  as they are untimed. Basically, it causes a race condition.
  ... As of now, I have no idea how to fix this part.
- I just read about essentially relaying requests 

## 03/16/2025

- I am still writing some documentation on this project as to
  help me make sense of this as I try to implement this into an actual project.
  Websockets are useful, but I haven't tested it properly with another computer.
- I have just started to try to generalize the process of synchronizing data upon entry.
  However, I haven't actually checked it fully, so I need to go over the logic one more time.
  (Especially on the strings used in message passing. It is very hard to keep track of.)
- Hopefully, this works.