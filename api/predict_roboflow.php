<?php

declare(strict_types=1);

header('Content-Type: application/json; charset=utf-8');
header('Access-Control-Allow-Origin: *');
header('Access-Control-Allow-Methods: POST, OPTIONS');
header('Access-Control-Allow-Headers: Content-Type, Accept');

function sendRoboflowResponse(bool $success, string $message, array $data = [], int $status = 200): never
{
    http_response_code($status);
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
    sendRoboflowResponse(false, 'Only POST requests are allowed.', [], 405);
}
if (!isset($_FILES['image'])) {
    sendRoboflowResponse(false, 'No image was uploaded.', [], 400);
}

$image = $_FILES['image'];
if ($image['error'] !== UPLOAD_ERR_OK) {
    sendRoboflowResponse(false, 'Image upload failed. Please try again.', [], 400);
}
if ($image['size'] > 8 * 1024 * 1024) {
    sendRoboflowResponse(false, 'Image must not exceed 8 MB.', [], 400);
}

$finfo = new finfo(FILEINFO_MIME_TYPE);
$mimeType = $finfo->file($image['tmp_name']);
if (!in_array($mimeType, ['image/jpeg', 'image/png', 'image/webp'], true)) {
    sendRoboflowResponse(false, 'Unsupported image type. Use JPG, PNG, or WEBP.', [], 400);
}

require_once __DIR__ . '/roboflow_workflow.php';
set_time_limit(90);

$imageBytes = file_get_contents($image['tmp_name']);
if ($imageBytes === false) {
    sendRoboflowResponse(false, 'Unable to read the uploaded image.', [], 500);
}

try {
    $outputs = runRoboflowWorkflowImage($imageBytes);
    sendRoboflowResponse(true, 'Roboflow prediction successful.', [
        'workflow' => ROBOFLOW_WORKFLOW_ID,
        'outputs' => $outputs,
    ]);
} catch (RoboflowWorkflowException $exception) {
    error_log('Roboflow workflow error: ' . $exception->getMessage());
    sendRoboflowResponse(false, 'The AI could not analyze this photo right now. Please choose a category yourself.', [], 502);
} catch (Throwable $exception) {
    error_log('Roboflow prediction error: ' . $exception->getMessage());
    sendRoboflowResponse(false, 'Unable to process the Roboflow prediction.', [], 500);
}

