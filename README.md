# citisense

A new Flutter project.

## Roboflow image predictions

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
