<?php

declare(strict_types=1);

const ROBOFLOW_WORKSPACE = 'druviss-workspace';
const ROBOFLOW_WORKFLOW_ID = 'citisense-stvbw-2-yolo11s-t1-vcitisense-stvbw-2-yolo11s-t1-logic';
const ROBOFLOW_WORKFLOW_URL = 'https://serverless.roboflow.com/druviss-workspace/workflows/' . ROBOFLOW_WORKFLOW_ID;

class RoboflowWorkflowException extends RuntimeException
{
    public function __construct(string $message, public readonly ?int $httpStatus = null)
    {
        parent::__construct($message);
    }
}

/**
 * Run the published CitiSense Roboflow workflow on image bytes.
 * The workflow currently declares only the `image` input and no parameters.
 * Returns the first result's output map without assuming output names.
 *
 * @return array<string, mixed>
 */
function runRoboflowWorkflowImage(string $imageBytes): array
{
    $apiKey = getenv('ROBOFLOW_API_KEY');
    if ($apiKey === false || trim($apiKey) === '') {
        throw new RoboflowWorkflowException('ROBOFLOW_API_KEY is not configured.');
    }
    if ($imageBytes === '') {
        throw new InvalidArgumentException('Image data cannot be empty.');
    }

    $payload = json_encode([
        'inputs' => [
            'image' => [
                'type' => 'base64',
                'value' => base64_encode($imageBytes),
            ],
        ],
    ], JSON_THROW_ON_ERROR);

    $maxRetries = 2;
    $retryDelays = [1, 2];
    $retryableStatuses = [408, 429, 500, 502, 503, 504];

    for ($attempt = 0; $attempt <= $maxRetries; $attempt++) {
        $curl = curl_init(ROBOFLOW_WORKFLOW_URL);
        if ($curl === false) {
            throw new RoboflowWorkflowException('Unable to initialize the Roboflow request.');
        }

        curl_setopt_array($curl, [
            CURLOPT_RETURNTRANSFER => true,
            CURLOPT_POST => true,
            CURLOPT_POSTFIELDS => $payload,
            CURLOPT_HTTPHEADER => [
                'Content-Type: application/json',
                'Authorization: Bearer ' . $apiKey,
            ],
            CURLOPT_CONNECTTIMEOUT => 10,
            CURLOPT_TIMEOUT => 60,
        ]);

        $body = curl_exec($curl);
        $curlError = curl_error($curl);
        $httpStatus = (int) curl_getinfo($curl, CURLINFO_HTTP_CODE);
        curl_close($curl);

        if ($body !== false && $httpStatus >= 200 && $httpStatus < 300) {
            try {
                $response = json_decode($body, true, 512, JSON_THROW_ON_ERROR);
            } catch (JsonException $exception) {
                throw new RoboflowWorkflowException('Roboflow returned invalid JSON.', $httpStatus);
            }

            // The serverless Workflow API returns one output map per input image.
            // Also accept an `outputs` wrapper in case the API wraps that list.
            $results = $response['outputs'] ?? $response;
            $firstResult = is_array($results) ? ($results[0] ?? null) : null;
            if (!is_array($firstResult)) {
                throw new RoboflowWorkflowException('Roboflow response did not contain a result for the uploaded image.', $httpStatus);
            }

            return $firstResult;
        }

        $retryable = $body === false || in_array($httpStatus, $retryableStatuses, true);
        if (!$retryable || $attempt === $maxRetries) {
            $message = $body === false
                ? 'Could not connect to Roboflow: ' . $curlError
                : 'Roboflow workflow request failed with HTTP ' . $httpStatus . '.';
            throw new RoboflowWorkflowException($message, $httpStatus ?: null);
        }

        sleep($retryDelays[$attempt]);
    }

    throw new RoboflowWorkflowException('Roboflow workflow request failed.');
}

