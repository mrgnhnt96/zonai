# Doc-snippet scaffolds

The surrounding code that a doc *fragment* is spliced into before it is handed
to the analyzer. A fragment names the one it belongs in on its own fence:

````
```dart in:extension-user
@override
Future<void> onSignUp(User user, Jwt? jwt) async {
  // ...
}
```
````

`in:extension-user` resolves to `extension-user.dart` here, and the fragment
replaces its `// <<body>>` line.

## Rules for a scaffold

- **It must be a real, analyzable Dart file on its own.** `doc_snippets_test`
  analyzes every scaffold with an empty body alongside the snippets, and
  reports a failure there as scaffold rot rather than as drift in the dozen
  docs spliced into it.
- **It carries the imports, not the fragment.** Fragments in prose don't repeat
  imports, so the scaffold supplies them — written the way a reader's own
  project would (`package:my_app/...`), which `doc_snippets_test` rewrites to
  the playground's tables or to `../doc_snippets` fixtures.
- **It may declare bindings the prose assumes** (a `client`, a `user`) when a
  page's fragments read as a continuation of an earlier example. Keep those to
  what the prose actually implies: a binding invented here is context the
  reader never sees, and a snippet that only compiles because of it is being
  checked against the wrong thing.
- **One scaffold per shape, named for it.** `extension-user`, not `ext1`. The
  name appears in every doc that uses it.

Adding a scaffold is cheap. Loosening one — widening a type, stubbing a member
so a fragment stops failing — usually means the fragment is drifting and the
scaffold is being bent to hide it.
