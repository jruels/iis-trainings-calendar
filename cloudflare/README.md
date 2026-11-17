# IIS Trainings calendar on Cloudflare

A private, full-screen web app for the calendar, served by a Cloudflare
Worker:

- `public/` holds the calendar page, icon and manifest.
- `/api/trainings` reads the Trainings, Bootcamps and Completed Courses
  boards from monday, using a secret token stored in Cloudflare.
- Cloudflare Access puts an email sign-in in front of everything. Only
  addresses you list can open it, and your monday token never reaches the
  phone.

Every step below can be done in a phone browser.

## 1. Deploy the Worker from GitHub

1. In the Cloudflare dashboard, go to **Workers & Pages**, then **Create**,
   then **Import a repository**. Connect GitHub if asked, and pick
   `jruels/iis-trainings-calendar`.
2. Fill in:
   - **Project name:** `iis-trainings` (must match `name` in `wrangler.jsonc`)
   - **Production branch:** the branch the code is on (today
     `claude/ios-training-calendar-app-wwiwiu`; switch to `main` after merging)
   - **Root directory** (under advanced settings): `cloudflare`
   - **Build command:** leave empty
   - **Deploy command:** `npx wrangler deploy` (the default)
3. Tap **Deploy**. When it finishes you get an address like
   `https://iis-trainings.<your-subdomain>.workers.dev`.

From then on, every push to that branch redeploys automatically.

## 2. Add the monday token

1. In monday, go to your avatar, then **Developers**, then **My access
   tokens**, and copy the token.
2. In Cloudflare, open the `iis-trainings` Worker, then **Settings**, then
   **Variables and Secrets**, then **Add**.
3. Set **Type** to **Secret**, **Name** to `MONDAY_API_TOKEN`, and paste the
   token as the value. Tap **Deploy**.

## 3. Lock it with Cloudflare Access

1. In the Worker, go to **Settings**, then **Domains & Routes**. On the
   `workers.dev` row, turn on **Cloudflare Access** (sometimes labelled
   "Enable Cloudflare Access"). This creates an Access application for the
   address.
2. Open **Zero Trust**, then **Access**, then **Applications**, and edit that
   application.
   - **Policy:** Action **Allow**, Include **Emails**, then your email (add
     anyone else who should see the calendar).
   - **Login method:** One-time PIN is fine. It emails you a code.
   - **Session duration:** something long, such as 1 month, so the phone
     stays signed in.
3. Save.

The Worker also refuses `/api/trainings` without an Access sign-in, so if
Access were ever switched off, the data would stay closed.

### Recommended: full token verification

In the Access application's overview, copy the **Application Audience (AUD)
tag**. Your team domain is shown under **Zero Trust**, then **Settings**
(for example `yourteam.cloudflareaccess.com`). Put both into the `vars`
block in `wrangler.jsonc` (or send them to Claude to commit):

```jsonc
"vars": {
  "ACCESS_TEAM_DOMAIN": "yourteam.cloudflareaccess.com",
  "ACCESS_AUD": "…"
}
```

With these set, the Worker checks every sign-in token's signature, audience
and expiry itself.

## 4. Put it on your iPhone

1. Open the `workers.dev` address in **Safari** and sign in with the emailed
   code.
2. Tap **Share**, then **Add to Home Screen**.

It opens full screen with its own icon. If the Home Screen app ever loops on
the sign-in page (iOS keeps Home Screen apps' cookies separate from
Safari's), sign in once inside the app. If it still loops, use it as a
Safari tab instead.

## Updating the page

The page source lives in `web/index.html`; it's the same file as the
claude.ai version. After editing it, run:

```
python3 web/build_cloudflare.py
```

Then commit. Cloudflare redeploys on push.

## Local development

```
cd cloudflare
npm install
echo 'MONDAY_API_TOKEN=…' > .dev.vars
npx wrangler dev
```

When testing locally, send any value in a `Cf-Access-Jwt-Assertion` header
(for example with curl), because there's no Access in front of `wrangler dev`.
