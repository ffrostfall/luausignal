# Changelog

### 0.5.0

- Fixed a niche bug where disconnecting multiple connections in the same fire would break
  - The solution is to iterate over connections in reverse. This breaks backwards compatibility, so a bump is needed.

### 0.4.0

- Added :delete()
- Added an error table
- Disconnects now use table.find over looping
- Added an assert check to :wait() to check if the coroutine was resumed

### 0.3.0

- Rewrite
- Added :wait()
- Added :disconnectAll()
- Added tests

### Past History

- the changelog was not kept very well before this point, so there isn't much of a point.
