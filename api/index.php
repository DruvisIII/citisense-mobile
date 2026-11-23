<?php

header('Content-Type: application/json');

require_once __DIR__ . '/config.php';

echo json_encode([
    'success' => true,
    'message' => 'CitiSense API is running!',
    'database' => 'Connected successfully'
]);
