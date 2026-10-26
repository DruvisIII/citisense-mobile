<?php

error_reporting(E_ALL);
ini_set('display_errors', 1);

header("Content-Type: application/json");
header("Access-Control-Allow-Origin: *");
header("Access-Control-Allow-Methods: GET, OPTIONS");
header("Access-Control-Allow-Headers: Content-Type, Accept");

// Handle CORS preflight request
if ($_SERVER["REQUEST_METHOD"] === "OPTIONS") {
    http_response_code(200);
    exit;
}

require_once "config.php";

$sql = "SELECT barangayID, barangayName 
        FROM barangay 
        ORDER BY barangayName ASC";

$result = $conn->query($sql);

if (!$result) {
    echo json_encode([
        "success" => false,
        "message" => "Failed to retrieve barangays."
    ]);
    exit;
}

$barangays = [];

while ($row = $result->fetch_assoc()) {
    $barangays[] = [
        "barangayID" => $row["barangayID"],
        "barangayName" => $row["barangayName"]
    ];
}

echo json_encode([
    "success" => true,
    "data" => $barangays
]);

$conn->close();

?>

