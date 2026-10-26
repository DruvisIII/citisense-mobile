<?php

error_reporting(E_ALL);
ini_set('display_errors', 1);

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

$firstName = trim($_POST["firstName"] ?? "");
$lastName = trim($_POST["lastName"] ?? "");
$email = trim($_POST["email"] ?? "");
$password = $_POST["password"] ?? "";
$contactNo = trim($_POST["contactNo"] ?? "");
$barangayID = $_POST["barangayID"] ?? "";

if (
    empty($firstName) ||
    empty($lastName) ||
    empty($email) ||
    empty($password) ||
    empty($contactNo) ||
    empty($barangayID)
) {
    echo json_encode([
        "success" => false,
        "message" => "Please complete all required fields."
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

/*
|--------------------------------------------------------------------------
| Check if email already exists
|--------------------------------------------------------------------------
*/

$checkSql = "SELECT userID FROM users WHERE email = ?";

$checkStmt = $conn->prepare($checkSql);
$checkStmt->bind_param("s", $email);
$checkStmt->execute();

$checkResult = $checkStmt->get_result();

if ($checkResult->num_rows > 0) {
    echo json_encode([
        "success" => false,
        "message" => "Email is already registered."
    ]);

    $checkStmt->close();
    $conn->close();
    exit;
}

$checkStmt->close();

/*
|--------------------------------------------------------------------------
| Generate User ID
|--------------------------------------------------------------------------
|
| Existing IDs:
| USR001
| USR002
| USR003
| USR004
|
| Next:
| USR005
|
*/

$idSql = "
    SELECT userID
    FROM users
    WHERE userID LIKE 'USR%'
    ORDER BY CAST(SUBSTRING(userID, 4) AS UNSIGNED) DESC
    LIMIT 1
";

$idStmt = $conn->prepare($idSql);
$idStmt->execute();

$idResult = $idStmt->get_result();

if ($idResult->num_rows > 0) {

    $row = $idResult->fetch_assoc();

    $lastUserID = $row["userID"];

    // Get the number after "USR"
    $lastNumber = intval(substr($lastUserID, 3));

    // Add 1
    $nextNumber = $lastNumber + 1;

} else {

    // No USR users yet
    $nextNumber = 1;
}

// Format as USR001, USR002, etc.
$userID = "USR" . str_pad($nextNumber, 3, "0", STR_PAD_LEFT);

$idStmt->close();

/*
|--------------------------------------------------------------------------
| Hash password
|--------------------------------------------------------------------------
*/

$hashedPassword = password_hash($password, PASSWORD_DEFAULT);

$profilePic = null;

/*
|--------------------------------------------------------------------------
| Insert new user
|--------------------------------------------------------------------------
*/

$sql = "INSERT INTO users
        (userID, firstName, lastName, email, pass, contactNo, profilePic, barangayID)
        VALUES (?, ?, ?, ?, ?, ?, ?, ?)";

$stmt = $conn->prepare($sql);

$stmt->bind_param(
    "ssssssss",
    $userID,
    $firstName,
    $lastName,
    $email,
    $hashedPassword,
    $contactNo,
    $profilePic,
    $barangayID
);

if ($stmt->execute()) {

    echo json_encode([
        "success" => true,
        "message" => "Account created successfully.",
        "userID" => $userID
    ]);

} else {

    echo json_encode([
        "success" => false,
        "message" => "Failed to create account."
    ]);
}

$stmt->close();
$conn->close();

?>
