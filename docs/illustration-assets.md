# Welcome illustrations

The supplied job-app visual is the style reference. These are newly generated illustrations, not a flattened screenshot of the interface. The Arabic heading, dotted path, controls, gradient background and accessibility remain Flutter widgets.

## Generation mode and files

Built-in `image_gen` generation mode was used for both assets. No CLI, API key or external download was used. PNG alpha was preserved, and both selected outputs were visually inspected before copying into the app.

- [Career robot](../assets/images/career-robot.png): portrait RGBA PNG, resized for the welcome screen. Metallic blue robot, wood desk, unbranded laptop and warm brown chair.
- Career search magnifying-glass artwork is no longer bundled; the welcome screen uses the robot only.
- [Welcome screen](../lib/features/jobs/presentation/welcome.dart): a single first-run robot-led page with the Sanad logo, one primary action, reduced-motion support and scrollable compact/large-text layouts. The latest design removes the separate skip action and diagonal CTA arrow.

The original RGBA robot remains unchanged. Flutter composes it with the Sanad logo, an opportunity card and short reveal transitions. The two surrounding accents drift gently at independent periods; the robot and text stay steady. TickerMode, app lifecycle and Reduce Motion suspend decorative motion.

## Final robot prompt

```text
Use case: stylized-concept. Asset type: transparent cutout PNG illustration for the lower half of a premium job-search mobile app welcome page. Generate a polished 3D metallic BLUE friendly small humanoid robot seated on a honey-brown padded office chair at a simple light warm wood rectangular desk, using an open unbranded graphite-gray laptop. The robot is on the RIGHT half, laptop on the LEFT half. Camera front three-quarter view at desktop height, robot turned a little toward viewer. Round oval head with dark blue segmented crown, glossy cyan-rimmed round dark eyes, small cheerful closed smile, blue articulated arms, one hand on keyboard, other on wood desk. Smooth cobalt and sky-blue metal with deep navy joints and subtle turquoise highlights. Desk runs diagonally from front-left toward right; slim dark metallic table legs. Keep the whole illustration within canvas, no cropped head, hands or desktop. Robot head is near upper-right of illustration, laptop slightly lower on left, desk stretches across full width at middle-lower height, legs end near bottom. Crisp high-quality 3D product rendering, physically plausible toy-like materials, softly lit from top left with gentle ambient shadows only on objects. The scene should feel sophisticated and welcoming, matching a misty blue glassmorphism mobile interface. Composition: portrait 4:5 cutout, objects nearly fill canvas, little empty padding. Background MUST be genuinely transparent with alpha, no checkerboard painted in, no colored background plane, no ground, no room, no surrounding interface. No typography, no watermark, no logos, no additional objects or characters.
```

## Final search prompt

```text
Use case: stylized-concept. Asset type: small transparent 3D decorative illustration for a job-search app welcome screen. One large magnifying glass with a glossy midnight-blue and periwinkle-blue circular frame, clear slightly magnifying glass lens, and a short glossy golden-yellow handle angled diagonally DOWN RIGHT at 45 degrees. Inside the glass appears a simple golden-yellow anonymous person avatar bust: round yellow spherical head and rounded yellow shoulders, dark warm reddish inset behind shoulders. It resembles a friendly career search icon. Three-quarter dimensional angle, frame casts delicate shadows on the lens, polished toy-like 3D product rendering, soft studio illumination from upper left, silky blue plastic frame and yellow plastic handle. Shape nearly fills a square canvas with little padding. Background MUST be genuinely transparent alpha; no painted checkerboard, no floor, no backdrop or shadow plane. No words, letters, logos, watermark, interface, decorative stars, or extra objects.
```
