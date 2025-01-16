## 01/17/2025

- Unfortunately, the request-completer pattern does not work with the HTTP requests,
  as they are untimed. Basically, it causes a race condition.
  ... As of now, I have no idea how to fix this part.
- I just read about essentially relaying requests 