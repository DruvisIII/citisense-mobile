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

if ($_SERVER["REQUEST_METHOD"] !== "GET") {
    sendResponse(
        false,
        "Only GET requests are allowed.",
        null,
        405
    );
}

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

$sql = "
    SELECT
        r.reportID,
        r.userID,
        r.barangayID,
        r.categoryID,
        r.statusID,
        r.locationID,
        r.title,
        r.description,
        r.noOfReports,
        r.dateReported,
        r.timeline,

        c.categoryName,

        s.statusName,

        l.latitude,
        l.longitude,
        l.address,

        ri.imagesID,
        ri.imagePath,
        ri.uploadedAt

    FROM reports r

    LEFT JOIN categories c
        ON r.categoryID = c.categoryID

    LEFT JOIN stats s
        ON r.statusID = s.statusID

    LEFT JOIN location l
        ON r.locationID = l.locationID

    LEFT JOIN (
        SELECT
            reportID,
            MIN(imagesID) AS firstImageID
        FROM reportImages
        GROUP BY reportID
    ) firstImage
        ON r.reportID = firstImage.reportID

    LEFT JOIN reportImages ri
        ON ri.imagesID = firstImage.firstImageID

    WHERE r.userID = ?

    ORDER BY r.dateReported DESC
";

$stmt = $conn->prepare($sql);

if (!$stmt) {
    sendResponse(
        false,
        "Failed to prepare reports query.",
        null,
        500
    );
}

$stmt->bind_param("s", $userID);

if (!$stmt->execute()) {
    $stmt->close();

    sendResponse(
        false,
        "Failed to retrieve your reports.",
        null,
        500
    );
}

$result = $stmt->get_result();

$reports = [];

while ($row = $result->fetch_assoc()) {

    $status = $row["statusName"] ?? "";

    if ($status === "Pending") {
        $displayStatus = "Pending";
    } elseif ($status === "In Progress") {
        $displayStatus = "In Progress";
    } elseif ($status === "Resolved") {
        $displayStatus = "Complete";
    } else {
        $displayStatus = $status;
    }

    $reports[] = [
        "reportID" => $row["reportID"],
        "userID" => $row["userID"],
        "barangayID" => $row["barangayID"],
        "categoryID" => $row["categoryID"],
        "categoryName" => $row["categoryName"],
        "statusID" => $row["statusID"],
        "statusName" => $status,
        "displayStatus" => $displayStatus,
        "locationID" => $row["locationID"],
        "title" => $row["title"],
        "description" => $row["description"],
        "noOfReports" => $row["noOfReports"],
        "dateReported" => $row["dateReported"],
        "timeline" => $row["timeline"],
        "latitude" => $row["latitude"],
        "longitude" => $row["longitude"],
        "address" => $row["address"],
        "imagesID" => $row["imagesID"],
        "imagePath" => $row["imagePath"],
        "uploadedAt" => $row["uploadedAt"]
    ];
}

$stmt->close();
$conn->close();

sendResponse(
    true,
    "Reports retrieved successfully.",
    $reports
);

?>