# citisense

A new Flutter project.

## Railway email variables

Railway blocks outbound SMTP on the Free, Trial and Hobby plans, so Gmail SMTP cannot deliver OTPs there. `api/mailer.php` picks the first configured option:

1. `GMAIL_SCRIPT_URL` + `GMAIL_SCRIPT_SECRET`: free, sends from your Gmail through a Google Apps Script (below).
2. `BREVO_API_KEY` + `MAIL_FROM_EMAIL`: Brevo's email API.
3. `GMAIL_ADDRESS` + `GMAIL_APP_PASSWORD`: Gmail SMTP (XAMPP, or Railway Pro).

### Free Gmail sending

1. Signed in to the Gmail account that should send the codes, open https://script.google.com and create a new project.
2. Replace the editor contents with `tools/gmail_relay.gs` and save.
3. Project Settings → Script Properties → add `SECRET` with a long random value.
4. In the editor, choose the `authorize` function, click Run, and allow the Gmail permission.
5. Deploy → New deployment → type **Web app**; Execute as **Me**; Who has access **Anyone**. Copy the Web app URL (ends in `/exec`).
6. In Railway, set `GMAIL_SCRIPT_URL` to that URL and `GMAIL_SCRIPT_SECRET` to the same secret.

Free Gmail accounts can send about 100 emails a day this way. If you edit the script later, deploy a new version (Deploy → Manage deployments → Edit → New version) so the URL keeps working.

## Push notifications and announcement pictures (Railway)

API service variables:

| Variable | Used for |
| --- | --- |
| `FIREBASE_SERVICE_ACCOUNT_JSON` | Whole Firebase service-account JSON file (raw or base64) for sending pushes |
| `PUSH_DISPATCH_SECRET` | Long random value that protects `push_dispatch.php` |
| `ANNOUNCEMENT_MEDIA_BASE_URL` | Admin website address, e.g. `https://<admin>.up.railway.app/`. `media.php` downloads announcement pictures and admin profile pictures from there when they are not on the API server |
| `UPLOAD_ROOT` (optional) | The API's `uploads` folder on a persistent volume, e.g. `/data/uploads`. Report photos and residents' profile pictures are saved there |
| `API_PUBLIC_URL` (optional) | The API's public address, if picture links built from the request's host are wrong (e.g. behind a proxy) |

### Pictures in the app

The app loads announcement pictures and profile pictures through `media.php?p=uploads/...`. It serves only `uploads/announcements/`, `uploads/profile/` and `uploads/profile_pictures/`. It looks on this server first (the API folder, its parent folder, `UPLOAD_ROOT`, and on XAMPP the admin website's folder in `htdocs`), then on the admin website (`ANNOUNCEMENT_MEDIA_BASE_URL`).

If the admin website keeps its uploads on a volume outside its web folder (`CS_UPLOAD_ROOT`), its pictures are only reachable through its login-protected `admin/media.php`. In that case mount the admin volume on the admin site's `uploads` folder (Railway: `/app/uploads`), as the admin README recommends, so `https://<admin>/uploads/announcements/...` works.

### Staying logged in

`login.php` returns a session token. The app keeps it in the phone's secure storage (Android Keystore / iOS Keychain), never the password, and checks it with `session.php` (`action=restore`) when it opens. Sessions end after 30 days without use, after a password change, or with Log Out (`session.php`, `action=logout`, which also stops push notifications to that phone).

The admin panel saves report updates (`notification`) and announcements (`announcements`) without sending pushes. `push_dispatch.php?key=<PUSH_DISPATCH_SECRET>` sends a push for each new one, once, and records it in `push_sent_log`. Call it after the admin saves something, or on a schedule.



The PHP backend exposes `POST /api/predict_roboflow.php` for image predictions with the published CitiSense Roboflow Workflow. It accepts a multipart form upload with the field name `image` (JPG, PNG, or WebP; maximum 8 MB). The response returns the workflow's output map under `outputs`; the current published workflow output is named `predictions`.

Set `ROBOFLOW_API_KEY` in the PHP server process environment. Do not put the key in Flutter or commit it to this repository. For Apache on XAMPP, configure the variable for Apache itself (for example in its service environment), then restart Apache. The key is available from [Roboflow API settings](https://app.roboflow.com/settings/api).

To test with an image, download this pothole sample and submit it to the local PHP API:

```powershell
Invoke-WebRequest -Uri "https://upload.wikimedia.org/wikipedia/commons/1/1d/Potholes.jpg" -OutFile "$env:TEMP\sample-potholes.jpg"
curl.exe -X POST -F "image=@$env:TEMP\sample-potholes.jpg" http://localhost/citisense/api/predict_roboflow.php
```

The sample photo is by Matt RF Webb and is licensed under [CC BY-SA 4.0](https://creativecommons.org/licenses/by-sa/4.0/) ([source](https://commons.wikimedia.org/wiki/File:Potholes.jpg)).

The PHP CLI smoke test runs the same workflow request and checks that the published `predictions` output exists:

```powershell
php api/test_roboflow_workflow.php "$env:TEMP\sample-potholes.jpg"
```

The workflow declares a single `image` input and no runtime parameters. Its serverless endpoint uses bearer-header authentication and runs the latest published workflow version.

## Getting Started

This project is a starting point for a Flutter application.

A few resources to get you started if this is your first Flutter project:

- [Learn Flutter](https://docs.flutter.dev/get-started/learn-flutter)
- [Write your first Flutter app](https://docs.flutter.dev/get-started/codelab)
- [Flutter learning resources](https://docs.flutter.dev/reference/learning-resources)

For help getting started with Flutter development, view the
[online documentation](https://docs.flutter.dev/), which offers tutorials,
samples, guidance on mobile development, and a full API reference.
