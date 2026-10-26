<?php

header("Content-Type: application/json");
header("Access-Control-Allow-Origin: *");
header("Access-Control-Allow-Methods: GET, OPTIONS");
header("Access-Control-Allow-Headers: Content-Type, Accept");

if ($_SERVER["REQUEST_METHOD"] === "OPTIONS") {
    http_response_code(200);
    exit;
}

require_once "config.php";

function sendResponse($success, $message, $data = null, $statusCode = 200)
{
    http_response_code($statusCode);

    $response = [
        "success" => $success,
        "message" => $message
    ];

    if ($data !== null) {
        $response["data"] = $data;
    }

    echo json_encode($response);
    exit;
}

/*
|--------------------------------------------------------------------------
| Only GET requests are allowed
|--------------------------------------------------------------------------
*/

if ($_SERVER["REQUEST_METHOD"] !== "GET") {
    sendResponse(
        false,
        "Only GET requests are allowed.",
        null,
        405
    );
}

/*
|--------------------------------------------------------------------------
| Get userID
|--------------------------------------------------------------------------
*/

$userID = isset($_GET["userID"])
    ? trim($_GET["userID"])
    : "";

if ($userID === "") {
    sendResponse(
        false,
        "User ID is required.",
        null,
        400
    );
}

/*
|--------------------------------------------------------------------------
| Get user information
|--------------------------------------------------------------------------
*/

$sql = "
    SELECT
        u.userID,
        u.firstName,
        u.lastName,
        u.email,
        u.contactNo,
        u.profilePic,
        u.barangayID,
        b.barangayName
    FROM users u
    LEFT JOIN barangay b
        ON u.barangayID = b.barangayID
    WHERE u.userID = ?
    LIMIT 1
";

$stmt = $conn->prepare($sql);

if (!$stmt) {
    sendResponse(
        false,
        "Failed to prepare user query.",
        null,
        500
    );
}

$stmt->bind_param("s", $userID);

if (!$stmt->execute()) {
    $stmt->close();

    sendResponse(
        false,
        "Failed to retrieve user information.",
        null,
        500
    );
}

$result = $stmt->get_result();

if ($result->num_rows === 0) {
    $stmt->close();

    sendResponse(
        false,
        "User not found.",
        null,
        404
    );
}

$user = $result->fetch_assoc();

$stmt->close();

/*
|--------------------------------------------------------------------------
| Return latest user information
|--------------------------------------------------------------------------
*/

sendResponse(
    true,
    "User profile retrieved successfully.",
    [
        "userID" => $user["userID"],
        "firstName" => $user["firstName"],
        "lastName" => $user["lastName"],
        "email" => $user["email"],
        "contactNo" => $user["contactNo"],
        "profilePic" => $user["profilePic"],
        "barangayID" => $user["barangayID"],
        "barangayName" => $user["barangayName"]
    ]
);

$conn->close();

?>