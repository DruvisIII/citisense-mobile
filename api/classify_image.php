<?php

declare(strict_types=1);

header('Content-Type: application/json; charset=utf-8');
header('Access-Control-Allow-Origin: *');
header('Access-Control-Allow-Methods: POST, OPTIONS');
header('Access-Control-Allow-Headers: Content-Type, Accept');

const ROBOFLOW_CLASSIFICATION_THRESHOLD = 0.70;

function sendResponse(bool $success, string $message, array $data = [], int $httpCode = 200): never
{
    http_response_code($httpCode);
    echo json_encode(array_merge([
        'success' => $success,
        'message' => $message,
    ], $data));
    exit;
}

if ($_SERVER['REQUEST_METHOD'] === 'OPTIONS') {
    http_response_code(200);
    exit;
}

if ($_SERVER['REQUEST_METHOD'] !== 'POST') {
    sendResponse(false, 'Only POST requests are allowed.', [], 405);
}

if (!isset($_FILES['image'])) {
    sendResponse(false, 'No image was uploaded.', [], 400);
}

$image = $_FILES['image'];
if ($image['error'] !== UPLOAD_ERR_OK) {
    sendResponse(false, 'Image upload failed. Please try again.', [
        'upload_error' => $image['error'],
    ], 400);
}

if ($image['size'] > 8 * 1024 * 1024) {
    sendResponse(false, 'Image must not exceed 8 MB.', [], 400);
}

$finfo = new finfo(FILEINFO_MIME_TYPE);
$mimeType = $finfo->file($image['tmp_name']);
if (!in_array($mimeType, ['image/jpeg', 'image/png', 'image/webp'], true)) {
    sendResponse(false, 'Unsupported image type. Use JPG, PNG, or WEBP.', [
        'detected_type' => $mimeType,
    ], 400);
}

$imageBytes = file_get_contents($image['tmp_name']);
if ($imageBytes === false) {
    sendResponse(false, 'Unable to read the uploaded image.', [], 500);
}

require_once __DIR__ . '/roboflow_workflow.php';
set_time_limit(90);

try {
    $outputs = runRoboflowWorkflowImage($imageBytes);
} catch (RoboflowWorkflowException $exception) {
    error_log('Roboflow classification error: ' . $exception->getMessage());
    sendResponse(false, 'The AI could not analyze this photo right now. Please choose a category yourself.', [], 502);
} catch (Throwable $exception) {
    error_log('Roboflow classification error: ' . $exception->getMessage());
    sendResponse(false, 'Unable to process the Roboflow classification.', [], 500);
}

// The published workflow returns an output map whose `predictions` value
// contains the detection list. Select its highest-confidence detection.
$detections = $outputs['predictions']['predictions'] ?? [];
if (!is_array($detections)) {
    $detections = [];
}

$bestDetection = null;
foreach ($detections as $detection) {
    if (!is_array($detection) || !isset($detection['confidence']) || !is_numeric($detection['confidence'])) {
        continue;
    }

    if ($bestDetection === null || (float) $detection['confidence'] > (float) $bestDetection['confidence']) {
        $bestDetection = $detection;
    }
}

$className = is_array($bestDetection) ? strtolower(trim((string) ($bestDetection['class'] ?? ''))) : '';
$confidence = is_array($bestDetection) ? (float) $bestDetection['confidence'] : null;

// Class labels are normalized above so matching is case-insensitive and
// ignores leading/trailing whitespace.
$categoryByClass = [
    'waste accumulation' => 'Waste Accumulation',
    'pothole' => 'Road Potholes',
];

if (
    isset($categoryByClass[$className]) &&
    $confidence !== null &&
    $confidence >= ROBOFLOW_CLASSIFICATION_THRESHOLD
) {
    $category = $categoryByClass[$className];
    sendResponse(true, 'Image classification successful!', [
        'model' => 'Roboflow',
        'category' => $category,
        'reason' => 'Roboflow detected ' . strtolower($category) . '.',
        'confidence' => $confidence,
    ]);
}

if ($bestDetection === null) {
    $reason = 'No detections were returned. Please choose a category manually.';
} elseif ($confidence < ROBOFLOW_CLASSIFICATION_THRESHOLD) {
    $reason = 'The detection confidence is below 0.70. Please choose a category manually.';
} else {
    $reason = 'The detected class is not mapped to a CitiSense category yet. Please choose a category manually.';
}

sendResponse(true, 'Image classification completed; please confirm the category.', [
    'model' => 'Roboflow',
    'category' => 'Others',
    'reason' => $reason,
    'confidence' => null,
]);

