public with sharing class DriveFileImporter {

    private static final String NC = 'callout:GoogleDriveNC';

    @future(callout=true)
    public static void importCV(Id leadId, String driveUrl) {
        importFileToLead(leadId, driveUrl, 'Imported_CV', 'Imported_CV.pdf');
    }

    @future(callout=true)
    public static void importMotivationLetter(Id leadId, String driveUrl) {
        importFileToLead(leadId, driveUrl, 'Motivation_Letter', 'Motivation_Letter.pdf');
    }

    private static void importFileToLead(Id leadId, String driveUrl, String title, String filename) {

        if (leadId == null || String.isBlank(driveUrl)) {
            return;
        }

        String fileId = extractDriveFileId(driveUrl);
        if (String.isBlank(fileId)) {
            return;
        }

        HttpRequest req = new HttpRequest();
        req.setMethod('GET');
        req.setEndpoint(NC + '/drive/v3/files/' + fileId + '?alt=media&acknowledgeAbuse=true');

        Http http = new Http();
        HttpResponse res = http.send(req);

        if (res.getStatusCode() != 200) {
            return;
        }

        Blob fileBody = res.getBodyAsBlob();

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

    private static String extractDriveFileId(String url) {

        Pattern p1 = Pattern.compile('/file/d/([a-zA-Z0-9_-]+)');
        Matcher m1 = p1.matcher(url);
        if (m1.find()) return m1.group(1);

        Pattern p2 = Pattern.compile('[\\?&]id=([a-zA-Z0-9_-]+)');
        Matcher m2 = p2.matcher(url);
        if (m2.find()) return m2.group(1);

        return null;
    }
}