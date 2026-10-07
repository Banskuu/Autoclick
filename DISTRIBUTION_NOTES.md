# Distribution notes

The automatic workflow produces a native Apple Silicon app and applies an
ad-hoc local signature. That is appropriate for private testing.

For the smoothest experience when distributing or selling Bubbles to other
people, the next production step is:

1. Apple Developer Program membership.
2. Developer ID Application signing.
3. Apple notarization.
4. Staple the notarization ticket to the app/DMG.

After that, users can normally open the downloaded app without the
unidentified-developer warning.
