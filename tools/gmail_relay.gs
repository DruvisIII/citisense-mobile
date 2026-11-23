// CitiSense Gmail relay (Google Apps Script).
// Sends the OTP emails from your own Gmail account, for free.
// Setup steps are in README.md under "Free Gmail sending".

function doPost(e) {
  var secret = PropertiesService.getScriptProperties().getProperty('SECRET');
  var data;

  try {
    data = JSON.parse(e.postData.contents);
  } catch (err) {
    return reply(false, 'Invalid JSON.');
  }

  if (!secret || data.secret !== secret) {
    return reply(false, 'Unauthorized.');
  }

  if (!data.to || !data.subject) {
    return reply(false, 'Missing recipient or subject.');
  }

  try {
    GmailApp.sendEmail(data.to, data.subject, data.text || '', {
      htmlBody: data.html || '',
      name: data.name || 'CitiSense'
    });
    return reply(true, 'Sent.');
  } catch (err) {
    return reply(false, String(err));
  }
}

function reply(success, message) {
  return ContentService
    .createTextOutput(JSON.stringify({ success: success, message: message }))
    .setMimeType(ContentService.MimeType.JSON);
}

// Run this once from the editor to grant Gmail permission.
function authorize() {
  GmailApp.getAliases();
}
