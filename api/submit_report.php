<?php

// ============================================================
// CORS AND JSON HEADERS
// ============================================================

header("Content-Type: application/json");
header("Access-Control-Allow-Origin: *");
header("Access-Control-Allow-Methods: POST, OPTIONS");
header("Access-Control-Allow-Headers: Content-Type, Accept");

// Handle browser preflight request
if ($_SERVER["REQUEST_METHOD"] === "OPTIONS") {
    http_response_code(200);
    exit;
}


// ============================================================
// ONLY ALLOW POST
// ============================================================

if ($_SERVER["REQUEST_METHOD"] !== "POST") {
    http_response_code(405);

    echo json_encode([
        "success" => false,
        "message" => "Only POST requests are allowed."
    ]);

    exit;
}


// ============================================================
// DATABASE CONNECTION
// ============================================================

require_once "config.php";


// ============================================================
// GET FORM DATA
// ============================================================

$userID = trim($_POST["userID"] ?? "");
$barangayID = trim($_POST["barangayID"] ?? "");
$categoryID = trim($_POST["categoryID"] ?? "");
$description = trim($_POST["description"] ?? "");

$latitude = $_POST["latitude"] ?? "";
$longitude = $_POST["longitude"] ?? "";

$address = trim($_POST["address"] ?? "");


// ============================================================
// VALIDATE REQUIRED FIELDS
// ============================================================

if ($userID === "") {
    echo json_encode([
        "success" => false,
        "message" => "User ID is required."
    ]);

    exit;
}

if ($barangayID === "") {
    echo json_encode([
        "success" => false,
        "message" => "Barangay ID is required."
    ]);

    exit;
}

if ($categoryID === "") {
    echo json_encode([
        "success" => false,
        "message" => "Category ID is required."
    ]);

    exit;
}

if ($latitude === "" || $longitude === "") {
    echo json_encode([
        "success" => false,
        "message" => "Location coordinates are required."
    ]);

    exit;
}


// ============================================================
// ADDRESS IS REQUIRED
// ============================================================

if ($address === "") {
    echo json_encode([
        "success" => false,
        "message" => "Address is required."
    ]);

    exit;
}


// ============================================================
// VALIDATE COORDINATES
// ============================================================

if (!is_numeric($latitude) || !is_numeric($longitude)) {
    echo json_encode([
        "success" => false,
        "message" => "Invalid latitude or longitude."
    ]);

    exit;
}

$latitude = (float) $latitude;
$longitude = (float) $longitude;


// ============================================================
// VALIDATE LATITUDE / LONGITUDE RANGE
// ============================================================

if ($latitude < -90 || $latitude > 90) {
    echo json_encode([
        "success" => false,
        "message" => "Latitude must be between -90 and 90."
    ]);

    exit;
}

if ($longitude < -180 || $longitude > 180) {
    echo json_encode([
        "success" => false,
        "message" => "Longitude must be between -180 and 180."
    ]);

    exit;
}


// ============================================================
// VALIDATE IMAGE
// ============================================================

if (!isset($_FILES["image"])) {
    echo json_encode([
        "success" => false,
        "message" => "Report image is required."
    ]);

    exit;
}

if ($_FILES["image"]["error"] !== UPLOAD_ERR_OK) {
    echo json_encode([
        "success" => false,
        "message" => "There was an error uploading the image."
    ]);

    exit;
}


// ============================================================
// IMAGE SIZE LIMIT
// 10 MB maximum
// ============================================================

$maxFileSize = 10 * 1024 * 1024;

if ($_FILES["image"]["size"] > $maxFileSize) {
    echo json_encode([
        "success" => false,
        "message" => "Image is too large. Maximum size is 10 MB."
    ]);

    exit;
}


// ============================================================
// VALIDATE IMAGE TYPE
// ============================================================

$tmpFile = $_FILES["image"]["tmp_name"];

$imageInfo = @getimagesize($tmpFile);

if ($imageInfo === false) {
    echo json_encode([
        "success" => false,
        "message" => "Uploaded file is not a valid image."
    ]);

    exit;
}

$allowedMimeTypes = [
    "image/jpeg",
    "image/png",
    "image/webp"
];

$mimeType = $imageInfo["mime"];

if (!in_array($mimeType, $allowedMimeTypes, true)) {
    echo json_encode([
        "success" => false,
        "message" => "Only JPG, PNG, and WebP images are allowed."
    ]);

    exit;
}


// ============================================================
// VALIDATE USER
// ============================================================

$stmt = $conn->prepare("
    SELECT userID
    FROM users
    WHERE userID = ?
    LIMIT 1
");

if (!$stmt) {
    echo json_encode([
        "success" => false,
        "message" => "Failed to prepare user validation."
    ]);

    exit;
}

$stmt->bind_param(
    "s",
    $userID
);

$stmt->execute();

$result = $stmt->get_result();

if ($result->num_rows === 0) {
    $stmt->close();

    echo json_encode([
        "success" => false,
        "message" => "User does not exist."
    ]);

    exit;
}

$stmt->close();


// ============================================================
// VALIDATE BARANGAY
// ============================================================

$stmt = $conn->prepare("
    SELECT barangayID
    FROM barangay
    WHERE barangayID = ?
    LIMIT 1
");

if (!$stmt) {
    echo json_encode([
        "success" => false,
        "message" => "Failed to prepare barangay validation."
    ]);

    exit;
}

$stmt->bind_param(
    "s",
    $barangayID
);

$stmt->execute();

$result = $stmt->get_result();

if ($result->num_rows === 0) {
    $stmt->close();

    echo json_encode([
        "success" => false,
        "message" => "Barangay does not exist."
    ]);

    exit;
}

$stmt->close();


// ============================================================
// VALIDATE CATEGORY
// ============================================================

$stmt = $conn->prepare("
    SELECT categoryID, categoryName
    FROM categories
    WHERE categoryID = ?
    LIMIT 1
");

if (!$stmt) {
    echo json_encode([
        "success" => false,
        "message" => "Failed to prepare category validation."
    ]);

    exit;
}

$stmt->bind_param(
    "s",
    $categoryID
);

$stmt->execute();

$result = $stmt->get_result();

if ($result->num_rows === 0) {
    $stmt->close();

    echo json_encode([
        "success" => false,
        "message" => "Category does not exist."
    ]);

    exit;
}

$categoryRow = $result->fetch_assoc();

$categoryName = $categoryRow["categoryName"];

$stmt->close();


// ============================================================
// GENERATE REPORT ID
// Example:
// REP001
// REP002
// REP003
// ============================================================

function generateNextID(
    mysqli $conn,
    string $table,
    string $column,
    string $prefix,
    int $numberLength = 3
): string {

    // These values are internal constants in this script,
    // so they are not coming directly from the user.

    $sql = "
        SELECT $column
        FROM $table
        WHERE $column LIKE ?
        ORDER BY CAST(
            SUBSTRING(
                $column,
                ?
            ) AS UNSIGNED
        ) DESC
        LIMIT 1
    ";

    $stmt = $conn->prepare($sql);

    if (!$stmt) {
        throw new Exception(
            "Unable to generate ID for $table."
        );
    }

    $likePattern = $prefix . "%";
    $prefixLength = strlen($prefix) + 1;

    $stmt->bind_param(
        "si",
        $likePattern,
        $prefixLength
    );

    $stmt->execute();

    $result = $stmt->get_result();

    $nextNumber = 1;

    if ($result->num_rows > 0) {

        $row = $result->fetch_assoc();

        $lastID = $row[$column];

        $numberPart = substr(
            $lastID,
            strlen($prefix)
        );

        $lastNumber = intval(
            $numberPart
        );

        $nextNumber = $lastNumber + 1;
    }

    $stmt->close();

    return $prefix .
        str_pad(
            $nextNumber,
            $numberLength,
            "0",
            STR_PAD_LEFT
        );
}


// ============================================================
// START DATABASE TRANSACTION
// ============================================================

$conn->begin_transaction();


// ============================================================
// VARIABLES FOR CLEANUP
// ============================================================

$uploadedFilePath = null;


try {

    // --------------------------------------------------------
    // GENERATE ALL REQUIRED IDs
    // --------------------------------------------------------

    $reportID = generateNextID(
        $conn,
        "reports",
        "reportID",
        "REP"
    );

    $locationID = generateNextID(
        $conn,
        "location",
        "locationID",
        "LOC"
    );

    $imagesID = generateNextID(
        $conn,
        "reportImages",
        "imagesID",
        "IMG"
    );

    $historyID = generateNextID(
        $conn,
        "reportHistory",
        "historyID",
        "HIS"
    );


    // --------------------------------------------------------
    // GENERATE REPORT TITLE
    // --------------------------------------------------------

    $title = $categoryName . " Report";


    // --------------------------------------------------------
    // DEFAULT VALUES
    // --------------------------------------------------------

    $statusID = "STAT001";

    $noOfReports = "1";


    // --------------------------------------------------------
    // CREATE UPLOAD DIRECTORY
    // --------------------------------------------------------

    $uploadDirectory =
        __DIR__ .
        DIRECTORY_SEPARATOR .
        ".." .
        DIRECTORY_SEPARATOR .
        "uploads" .
        DIRECTORY_SEPARATOR .
        "reports";

    $uploadDirectory =
        realpath(
            __DIR__ .
            DIRECTORY_SEPARATOR .
            ".."
        ) .
        DIRECTORY_SEPARATOR .
        "uploads" .
        DIRECTORY_SEPARATOR .
        "reports";


    if (!is_dir($uploadDirectory)) {

        if (!mkdir(
            $uploadDirectory,
            0777,
            true
        )) {
            throw new Exception(
                "Failed to create image upload directory."
            );
        }
    }


    // --------------------------------------------------------
    // DETERMINE IMAGE EXTENSION
    // --------------------------------------------------------

    switch ($mimeType) {

        case "image/jpeg":
            $extension = "jpg";
            break;

        case "image/png":
            $extension = "png";
            break;

        case "image/webp":
            $extension = "webp";
            break;

        default:
            throw new Exception(
                "Unsupported image type."
            );
    }


    // --------------------------------------------------------
    // IMAGE FILE NAME
    // --------------------------------------------------------

    $fileName =
        $reportID .
        "." .
        $extension;


    $destination =
        $uploadDirectory .
        DIRECTORY_SEPARATOR .
        $fileName;


    // --------------------------------------------------------
    // MOVE IMAGE
    // --------------------------------------------------------

    if (!move_uploaded_file(
        $tmpFile,
        $destination
    )) {
        throw new Exception(
            "Failed to save the report image."
        );
    }

    $uploadedFilePath = $destination;


    // --------------------------------------------------------
    // DATABASE IMAGE PATH
    // --------------------------------------------------------

    $imagePath =
        "uploads/reports/" .
        $fileName;


    // ========================================================
    // INSERT LOCATION
    // ========================================================

    $stmt = $conn->prepare("
        INSERT INTO location (
            locationID,
            latitude,
            longitude,
            address
        )
        VALUES (?, ?, ?, ?)
    ");

    if (!$stmt) {
        throw new Exception(
            "Failed to prepare location query."
        );
    }

    $stmt->bind_param(
        "sdds",
        $locationID,
        $latitude,
        $longitude,
        $address
    );

    if (!$stmt->execute()) {
        throw new Exception(
            "Failed to save location: " .
            $stmt->error
        );
    }

    $stmt->close();


    // ========================================================
    // INSERT REPORT
    // ========================================================

    $stmt = $conn->prepare("
        INSERT INTO reports (
            reportID,
            userID,
            barangayID,
            categoryID,
            statusID,
            locationID,
            title,
            description,
            noOfReports,
            dateReported,
            timeline
        )
        VALUES (
            ?,
            ?,
            ?,
            ?,
            ?,
            ?,
            ?,
            ?,
            ?,
            CURRENT_TIMESTAMP,
            CURRENT_TIMESTAMP
        )
    ");

    if (!$stmt) {
        throw new Exception(
            "Failed to prepare report query."
        );
    }

    $stmt->bind_param(
        "sssssssss",
        $reportID,
        $userID,
        $barangayID,
        $categoryID,
        $statusID,
        $locationID,
        $title,
        $description,
        $noOfReports
    );

    if (!$stmt->execute()) {
        throw new Exception(
            "Failed to save report: " .
            $stmt->error
        );
    }

    $stmt->close();


    // ========================================================
    // INSERT REPORT IMAGE
    // ========================================================

    $stmt = $conn->prepare("
        INSERT INTO reportImages (
            imagesID,
            reportID,
            imagePath,
            uploadedAt
        )
        VALUES (
            ?,
            ?,
            ?,
            CURRENT_TIMESTAMP
        )
    ");

    if (!$stmt) {
        throw new Exception(
            "Failed to prepare image query."
        );
    }

    $stmt->bind_param(
        "sss",
        $imagesID,
        $reportID,
        $imagePath
    );

    if (!$stmt->execute()) {
        throw new Exception(
            "Failed to save report image record: " .
            $stmt->error
        );
    }

    $stmt->close();


    // ========================================================
    // INSERT REPORT HISTORY
    // ========================================================

    $remarks = "Report submitted";

    $stmt = $conn->prepare("
        INSERT INTO reportHistory (
            historyID,
            reportID,
            userID,
            statusID,
            remarks,
            dateChanged
        )
        VALUES (
            ?,
            ?,
            ?,
            ?,
            ?,
            CURRENT_TIMESTAMP
        )
    ");

    if (!$stmt) {
        throw new Exception(
            "Failed to prepare report history query."
        );
    }

    $stmt->bind_param(
        "sssss",
        $historyID,
        $reportID,
        $userID,
        $statusID,
        $remarks
    );

    if (!$stmt->execute()) {
        throw new Exception(
            "Failed to save report history: " .
            $stmt->error
        );
    }

    $stmt->close();


    // ========================================================
    // COMMIT TRANSACTION
    // ========================================================

    $conn->commit();


    // ========================================================
    // SUCCESS RESPONSE
    // ========================================================

    echo json_encode([
        "success" => true,
        "message" => "Report submitted successfully.",
        "data" => [
            "reportID" => $reportID,
            "locationID" => $locationID,
            "imagesID" => $imagesID,
            "historyID" => $historyID,
            "imagePath" => $imagePath,
            "address" => $address
        ]
    ]);

} catch (Exception $e) {

    // ========================================================
    // ROLLBACK
    // ========================================================

    $conn->rollback();


    // ========================================================
    // DELETE UPLOADED IMAGE IF DATABASE FAILED
    // ========================================================

    if (
        $uploadedFilePath !== null &&
        file_exists($uploadedFilePath)
    ) {
        @unlink($uploadedFilePath);
    }


    // ========================================================
    // ERROR RESPONSE
    // ========================================================

    http_response_code(500);

    echo json_encode([
        "success" => false,
        "message" => $e->getMessage()
    ]);
}


// ============================================================
// CLOSE CONNECTION
// ============================================================

$conn->close();

?>