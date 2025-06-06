# ``SharingQuery``

A [Sharing](https://github.com/pointfreeco/swift-sharing) adapter for Swift Query.

## Overview

You can easily observe and interact with your queries using the ``SharedQuery`` property wrapper.

```swift
import SharingQuery

// This will begin fetching the post.
@SharedQuery(Post.query(for: 1)) var post

if $post.isLoading {
  print("Loading")
} else if let error = $post.error {
  print("Error", error)
} else {
  print("Post", post)
}
```
