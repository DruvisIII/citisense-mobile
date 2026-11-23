<?php

// ============================================================
// CITISENSE LOGIN API + FIREBASE FCM TOKEN REGISTRATION
// ============================================================

// Hide technical errors from users.
// Errors will still be recorded in the PHP/Apache error log.
error_reporting(E_ALL);
ini_set("display_errors", "0");

// ============================================================
// HEADERS
// ============================================================

header("Content-Type: application/json; charset=utf-8");
header("Access-Control-Allow-Origin: *");
header("Access-Control-Allow-Methods: POST, OPTIONS");
header("Access-Control-Allow-Headers: Content-Type, Accept");

if ($_SERVER["REQUEST_METHOD"] === "OPTIONS") {
    http_response_code(200);
    exit;
}

// ============================================================
// DATABASE CONNECTION
// ============================================================

require_once __DIR__ . "/config.php";

// ============================================================
// ONLY ALLOW POST REQUESTS
// ============================================================

if ($_SERVER["REQUEST_METHOD"] !== "POST") {
    http_response_code(405);

    echo json_encode([
        "success" => false,
        "message" => "Invalid request method."
    ]);

    exit;
}

// ============================================================
// RECEIVE LOGIN DATA FROM FLUTTER
// ============================================================

$email = trim($_POST["email"] ?? "");
$password = $_POST["password"] ?? "";
$fcmToken = trim($_POST["fcmToken"] ?? "");

// ============================================================
// VALIDATE LOGIN FIELDS
// ============================================================

if ($email === "" || $password === "") {
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

// ============================================================
// FIND USER BY EMAIL
// ============================================================

$sql = "
    SELECT
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
    LIMIT 1
";

try {

    $stmt = $conn->prepare($sql);

    if (!$stmt) {
        throw new RuntimeException(
            "Unable to prepare login query."
        );
    }

    $stmt->bind_param("s", $email);
    $stmt->execute();

    $result = $stmt->get_result();
    $user = $result->fetch_assoc();

    $stmt->close();

    // ========================================================
    // CHECK IF USER EXISTS
    // ========================================================

    if (!$user) {
        echo json_encode([
            "success" => false,
            "message" => "No account found with this email."
        ]);

        $conn->close();
        exit;
    }

    // ========================================================
    // VERIFY PASSWORD
    // ========================================================

    if (!password_verify($password, $user["pass"])) {
        echo json_encode([
            "success" => false,
            "message" => "Incorrect password."
        ]);

        $conn->close();
        exit;
    }

    // ========================================================
    // VALIDATE LOGGED-IN USER ID
    // ========================================================

    $loggedInUserID = trim(
        (string) ($user["userID"] ?? "")
    );

    // Prevent registration or login with an invalid user ID.
    if ($loggedInUserID === "") {
        error_log(
            "CitiSense login error: authenticated user has empty userID."
        );

        http_response_code(500);

        echo json_encode([
            "success" => false,
            "message" => "Unable to load your account information."
        ]);

        $conn->close();
        exit;
    }

    // ========================================================
    // REGISTER FCM TOKEN AFTER SUCCESSFUL LOGIN
    // ========================================================

    // Firebase token registration is optional.
    // Login must continue even if the token cannot be saved.

    if ($fcmToken !== "" && strlen($fcmToken) <= 512) {

        try {

            $tokenSql = "
                INSERT INTO user_device_tokens (
                    userID,
                    fcmToken
                )
                VALUES (?, ?)
                ON DUPLICATE KEY UPDATE
                    userID = VALUES(userID),
                    updatedAt = CURRENT_TIMESTAMP
            ";

            $tokenStmt = $conn->prepare($tokenSql);

            if (!$tokenStmt) {
                throw new RuntimeException(
                    "Unable to prepare FCM registration."
                );
            }

            $tokenStmt->bind_param(
                "ss",
                $loggedInUserID,
                $fcmToken
            );

            $tokenStmt->execute();
            $tokenStmt->close();

            error_log(
                "CitiSense FCM device registered for user: " .
                $loggedInUserID
            );

        } catch (Throwable $tokenError) {

            // Do not interrupt login.
            error_log(
                "CitiSense FCM token registration failed: " .
                $tokenError->getMessage()
            );
        }

    } else {

        error_log(
            "CitiSense FCM registration skipped: " .
            ($fcmToken === ""
                ? "No FCM token received."
                : "FCM token exceeds allowed length.")
        );
    }

    // ========================================================
    // LOGIN SUCCESSFUL
    // ========================================================

    // Preserve the exact JSON format expected by Flutter.

    echo json_encode([
        "success" => true,
        "message" => "Login successful.",
        "user" => [
            "userID" => $loggedInUserID,
            "firstName" => $user["firstName"],
            "lastName" => $user["lastName"],
            "email" => $user["email"],
            "contactNo" => $user["contactNo"],
            "profilePic" => $user["profilePic"],
            "barangayID" => $user["barangayID"]
        ]
    ]);

    $conn->close();

} catch (Throwable $e) {

    error_log(
        "CitiSense login failed: " . $e->getMessage()
    );

    http_response_code(500);

    echo json_encode([
        "success" => false,
        "message" => "Unable to process login. Please try again."
    ]);

    $conn->close();
}

?>
