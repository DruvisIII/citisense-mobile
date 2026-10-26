<?php

error_reporting(E_ALL);
ini_set('display_errors', 1);

    // header("Content-Type: application/json");

    // require_once "config.php";

header("Content-Type: application/json");
header("Access-Control-Allow-Origin: *");
header("Access-Control-Allow-Methods: POST, OPTIONS");
header("Access-Control-Allow-Headers: Content-Type, Accept");

if ($_SERVER["REQUEST_METHOD"] === "OPTIONS") {
    http_response_code(200);
    exit;
}

require_once "config.php";  

if ($_SERVER["REQUEST_METHOD"] !== "POST") {
    echo json_encode([
        "success" => false,
        "message" => "Invalid request method."
    ]);
    exit;
}

$email = trim($_POST["email"] ?? "");
$password = $_POST["password"] ?? "";

if (empty($email) || empty($password)) {
    echo json_encode([
        "success" => false,
        "message" => "Please enter your email and password."
    ]);
    exit;
}

if (!filter_var($email, FILTER_VALIDATE_EMAIL)) {
    echo json_encode([
        "success" => false,
        "message" => "Invalid email address."
    ]);
    exit;
}

// Find the user by email
$sql = "SELECT 
            userID,
            firstName,
            lastName,
            email,
            pass,
            contactNo,
            profilePic,
            barangayID
        FROM users
        WHERE email = ?
        LIMIT 1";

$stmt = $conn->prepare($sql);

if (!$stmt) {
    echo json_encode([
        "success" => false,
        "message" => "Database query failed."
    ]);
    exit;
}

$stmt->bind_param("s", $email);
$stmt->execute();

$result = $stmt->get_result();

if ($result->num_rows === 0) {
    echo json_encode([
        "success" => false,
        "message" => "No account found with this email."
    ]);

    $stmt->close();
    $conn->close();
    exit;
}

$user = $result->fetch_assoc();

// Verify password
if (!password_verify($password, $user["pass"])) {
    echo json_encode([
        "success" => false,
        "message" => "Incorrect password."
    ]);

    $stmt->close();
    $conn->close();
    exit;
}

// Login successful
echo json_encode([
    "success" => true,
    "message" => "Login successful.",
    "user" => [
        "userID" => $user["userID"],
        "firstName" => $user["firstName"],
        "lastName" => $user["lastName"],
        "email" => $user["email"],
        "contactNo" => $user["contactNo"],
        "profilePic" => $user["profilePic"],
        "barangayID" => $user["barangayID"]
    ]
]);

$stmt->close();
$conn->close();

?>

