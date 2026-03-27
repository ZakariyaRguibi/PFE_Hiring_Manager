public with sharing class DriveFileImportAction {

    // Must match your Named Credential API name
    private static final String NC = 'callout:GoogleDriveNC';

    public class Request {
        @InvocableVariable(required=true)
        public Id leadId;

        @InvocableVariable(required=false)
        public String cvUrl;

        @InvocableVariable(required=false)
        public String motivationUrl;
    }

    @InvocableMethod(
        label='Import CV + Motivation from Google Drive (Sync)'
        description='Downloads files from Google Drive links and attaches them to the Lead as Salesforce Files.'
    )
    public static void importFiles(List<Request> requests) {
        if (requests == null || requests.isEmpty()) return;

        for (Request r : requests) {
            if (r == null || r.leadId == null) continue;

            String cvUrl = (r.cvUrl == null) ? null : r.cvUrl.trim();
            String motUrl = (r.motivationUrl == null) ? null : r.motivationUrl.trim();

            if (String.isBlank(cvUrl) && String.isBlank(motUrl)) {
                // Flow will display this
                throw new CalloutException(
                    'Nothing to import. Fill CV Link and/or Motivation Letter Link with a Google Drive FILE link.'
                );
            }

            // 1) Callouts FIRST (no DML before callouts)
            Blob cvBlob;
            Blob motBlob;

            if (!String.isBlank(cvUrl)) {
                cvBlob = downloadDriveFile(cvUrl);
            }
            if (!String.isBlank(motUrl)) {
                motBlob = downloadDriveFile(motUrl);
            }

            // 2) DML AFTER callouts
            if (cvBlob != null) {
                attachBlobToLead(r.leadId, cvBlob, 'Imported_CV', 'Imported_CV.pdf');
            }
            if (motBlob != null) {
                attachBlobToLead(r.leadId, motBlob, 'Motivation_Letter', 'Motivation_Letter.pdf');
            }
        }
    }

    // -------------------------
    // Download from Google Drive
    // -------------------------
    private static Blob downloadDriveFile(String driveUrl) {
        String fileId = extractDriveFileId(driveUrl);

        if (String.isBlank(fileId)) {
            throw new CalloutException(
                'Invalid Google Drive URL. Use a FILE link like: https://drive.google.com/file/d/<FILE_ID>/view . ' +
                'Folder links and Google Docs links won’t work in this simple version.'
            );
        }

        HttpRequest req = new HttpRequest();
        req.setMethod('GET');
        req.setEndpoint(
            NC + '/drive/v3/files/' + EncodingUtil.urlEncode(fileId, 'UTF-8') +
            '?alt=media&acknowledgeAbuse=true'
        );

        Http http = new Http();
        HttpResponse res = http.send(req);

        if (res.getStatusCode() != 200) {
            String body = res.getBody();
            if (body != null && body.length() > 300) body = body.substring(0, 300);

            throw new CalloutException(
                'Drive download failed. StatusCode=' + res.getStatusCode() +
                ', Status=' + res.getStatus() +
                '. Make sure the file is shared as "Anyone with the link". Response=' + body
            );
        }

        return res.getBodyAsBlob();
    }

    // -------------------------
    // Attach as Salesforce File
    // -------------------------
    private static void attachBlobToLead(Id leadId, Blob fileBody, String title, String filename) {
        ContentVersion cv = new ContentVersion();
        cv.Title = title;
        cv.PathOnClient = filename;
        cv.VersionData = fileBody;
        insert cv;

        Id contentDocumentId = [
            SELECT ContentDocumentId
            FROM ContentVersion
            WHERE Id = :cv.Id
            LIMIT 1
        ].ContentDocumentId;

        ContentDocumentLink cdl = new ContentDocumentLink();
        cdl.LinkedEntityId = leadId;
        cdl.ContentDocumentId = contentDocumentId;
        cdl.ShareType = 'V';
        cdl.Visibility = 'AllUsers';
        insert cdl;
    }

    // -------------------------
    // Extract Drive FILE id
    // Supports:
    //  - /file/d/<id>
    //  - ?id=<id>
    // -------------------------
    private static String extractDriveFileId(String url) {
        if (String.isBlank(url)) return null;

        Pattern p1 = Pattern.compile('/file/d/([a-zA-Z0-9_-]+)');
        Matcher m1 = p1.matcher(url);
        if (m1.find()) return m1.group(1);

        Pattern p2 = Pattern.compile('[\\?&]id=([a-zA-Z0-9_-]+)');
        Matcher m2 = p2.matcher(url);
        if (m2.find()) return m2.group(1);

        return null;
    }
}