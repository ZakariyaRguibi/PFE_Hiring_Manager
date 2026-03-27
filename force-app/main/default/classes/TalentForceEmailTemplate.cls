public without sharing class TalentForceEmailTemplate {

private static final String LOGO_URL = 'https://res.cloudinary.com/dgy7mvhnm/image/upload/w_500,h_100,c_fit/v1773805978/talentforce_logo_header_4k_wmbyal.png';
    private static final String BLUE = '#2E86C1';
    private static final String ORANGE = '#E87722';

    // ═══════════════════════════════════════════
    // WRAPPER
    // ═══════════════════════════════════════════
    private static String wrapContent(
        String heroTitle,
        String heroSubtitle,
        String bodyHtml
    ) {
        return '<!DOCTYPE html>' +
        '<html><head><meta charset="UTF-8"/></head>' +
        '<body style="margin:0;padding:0;background-color:#ffffff;font-family:Arial,sans-serif;">' +

        // Top bars
        '<table width="100%" cellpadding="0" cellspacing="0">' +
        '<tr><td style="background-color:' + BLUE + ';height:5px;font-size:0;line-height:0;">&#160;</td></tr>' +
        '<tr><td style="background-color:' + ORANGE + ';height:3px;font-size:0;line-height:0;">&#160;</td></tr>' +
        '</table>' +

        // Logo bar
        '<table width="100%" cellpadding="0" cellspacing="0" style="background-color:#ffffff;">' +
        '<tr>' +
        '<td style="padding:20px 40px;">' +
        '<img src="' + LOGO_URL + '" height="44" alt="TalentForce Recruit" style="display:block;"/>' +
        '</td>' +
        '<td align="right" style="padding:20px 40px;font-size:11px;color:#999999;white-space:nowrap;">Recruitment Notification</td>' +
        '</tr>' +
        '</table>' +

        // Divider
        '<table width="100%" cellpadding="0" cellspacing="0">' +
        '<tr><td style="border-bottom:1px solid #eeeeee;font-size:0;line-height:0;">&#160;</td></tr>' +
        '</table>' +

        // Hero banner
        '<table width="100%" cellpadding="0" cellspacing="0" style="background-color:' + BLUE + ';">' +
        '<tr><td style="padding:36px 40px;text-align:center;">' +
        '<h1 style="margin:0 0 8px 0;font-size:26px;color:#ffffff;font-weight:bold;">' + heroTitle + '</h1>' +
        '<p style="margin:0;font-size:14px;color:#d6eaf8;">' + heroSubtitle + '</p>' +
        '</td></tr>' +
        '</table>' +

        // Orange accent
        '<table width="100%" cellpadding="0" cellspacing="0">' +
        '<tr><td style="background-color:' + ORANGE + ';height:4px;font-size:0;line-height:0;">&#160;</td></tr>' +
        '</table>' +

        // Body
        '<table width="100%" cellpadding="0" cellspacing="0" style="background-color:#ffffff;">' +
        '<tr><td style="padding:36px 40px;">' +
        bodyHtml +
        '</td></tr>' +
        '</table>' +

        // Footer
        '<table width="100%" cellpadding="0" cellspacing="0" style="background-color:#f8f8f8;border-top:1px solid #eeeeee;">' +
        '<tr>' +
        '<td style="padding:16px 40px;font-size:11px;color:#aaaaaa;">This email is confidential and intended solely for the named recipient.</td>' +
        '<td align="right" style="padding:16px 40px;font-size:11px;color:' + ORANGE + ';font-weight:bold;white-space:nowrap;">TalentForce Recruit</td>' +
        '</tr>' +
        '</table>' +

        // Bottom bars
        '<table width="100%" cellpadding="0" cellspacing="0">' +
        '<tr><td style="background-color:' + ORANGE + ';height:3px;font-size:0;line-height:0;">&#160;</td></tr>' +
        '<tr><td style="background-color:' + BLUE + ';height:5px;font-size:0;line-height:0;">&#160;</td></tr>' +
        '</table>' +

        '</body></html>';
    }

    // ═══════════════════════════════════════════
    // REUSABLE COMPONENTS
    // ═══════════════════════════════════════════
    private static String infoCard(List<String[]> rows) {
        String html =
        '<table width="100%" cellpadding="0" cellspacing="0" style="border-left:4px solid ' + BLUE + ';background-color:#f4f8fd;margin-bottom:24px;">' +
        '<tr><td style="padding:18px 22px;">' +
        '<table width="100%" cellpadding="0" cellspacing="0">';
        for (Integer i = 0; i < rows.size(); i++) {
            String borderStyle = (i < rows.size() - 1) ? 'border-bottom:1px solid #dde8f5;' : '';
            html +=
            '<tr>' +
            '<td style="padding:9px 0;' + borderStyle + 'font-size:13px;color:#888888;width:180px;">' + rows[i][0] + '</td>' +
            '<td style="padding:9px 0;' + borderStyle + 'font-size:13px;color:#2c2c2c;font-weight:bold;">' + rows[i][1] + '</td>' +
            '</tr>';
        }
        html += '</table></td></tr></table>';
        return html;
    }

    private static String orangeNotice(String message) {
        return
        '<table width="100%" cellpadding="0" cellspacing="0" style="border-left:4px solid ' + ORANGE + ';background-color:#fff8f0;margin-bottom:24px;">' +
        '<tr><td style="padding:14px 18px;">' +
        '<p style="margin:0;font-size:13px;color:#7a4a00;line-height:1.7;">' + message + '</p>' +
        '</td></tr></table>';
    }

    private static String greeting(String name) {
        return '<p style="font-size:15px;color:#2c2c2c;line-height:1.7;margin:0 0 20px 0;">Dear <strong>' + name + '</strong>,</p>';
    }

    private static String closing() {
        return
        '<p style="font-size:14px;color:#2c2c2c;line-height:1.7;margin:28px 0 0 0;">' +
        'Kind regards,<br/>' +
        '<strong style="color:' + BLUE + ';">TalentForce Recruit</strong><br/>' +
        '<span style="font-size:12px;color:#999999;">Recruitment Team</span>' +
        '</p>';
    }

    // ═══════════════════════════════════════════
    // 1. APPLICATION RECEIVED
    // ═══════════════════════════════════════════
    public static String applicationReceived(String candidateName, String positionName) {
        String body =
        greeting(candidateName) +
        '<p style="font-size:14px;color:#2c2c2c;line-height:1.7;margin:0 0 20px 0;">' +
        'Thank you for your application at <strong>TalentForce Recruit</strong>.' +
        '</p>' +
        infoCard(new List<String[]>{
            new String[]{ 'Position Applied', positionName }
        }) +
        '<p style="font-size:14px;color:#2c2c2c;line-height:1.7;margin:0 0 20px 0;">' +
        'Your profile is currently being reviewed by our recruitment team. ' +
        'If your application is selected, you will receive your login credentials and a password reset email ' +
        'allowing you to access our candidate portal and track your application.' +
        '</p>' +
        orangeNotice(
            'If you do not receive any communication from us within <strong>15 days</strong>, ' +
            'this means that your application was not retained for the next stage.'
        ) +
        closing();

        return wrapContent(
            'Thank You for Applying!',
            'We have received your application',
            body
        );
    }

    // ═══════════════════════════════════════════
    // 2. INTERVIEW INVITATION
    // ═══════════════════════════════════════════
    public static String interviewInvitation(
    String candidateName,
    String positionName,
    String interviewType,
    String interviewDate,
    String interviewEndTime,
    String interviewerName
) {
    String body =
    greeting(candidateName) +
    '<p style="font-size:14px;color:#2c2c2c;line-height:1.7;margin:0 0 20px 0;">' +
    'We are pleased to invite you to a <strong>' + interviewType + ' Interview</strong> ' +
    'for the position mentioned below. Please find the details of your interview:' +
    '</p>' +
    infoCard(new List<String[]>{
        new String[]{ 'Position', positionName },
        new String[]{ 'Interview Type', interviewType },
        new String[]{ 'Date &amp; Time', interviewDate },
        new String[]{ 'End Time', interviewEndTime },
        new String[]{ 'Interviewer', interviewerName }
    }) +
    orangeNotice(
        'Please confirm your attendance by replying to this email. ' +
        'If you are unable to attend at the scheduled time, contact us as soon as possible.'
    ) +
    closing();

    return wrapContent(
        interviewType + ' Interview Invitation',
        'You have been selected for a ' + interviewType + ' interview',
        body
    );
}
    // ═══════════════════════════════════════════
    // 3. SHORTLISTED
    // ═══════════════════════════════════════════
    public static String shortlisted(String candidateName, String positionName) {
        String body =
        greeting(candidateName) +
        '<p style="font-size:14px;color:#2c2c2c;line-height:1.7;margin:0 0 20px 0;">' +
        'We are pleased to inform you that following our evaluation process, ' +
        'your application has been <strong>shortlisted</strong> for the position below.' +
        '</p>' +
        infoCard(new List<String[]>{
            new String[]{ 'Position', positionName }
        }) +
        orangeNotice(
            'You are currently on our shortlist. You will be contacted if a position becomes available. ' +
            'Thank you for your patience.'
        ) +
        closing();

        return wrapContent(
            'You Have Been Shortlisted',
            'Your application is being considered',
            body
        );
    }

    // ═══════════════════════════════════════════
    // 4. CONTRACT SENT
    // ═══════════════════════════════════════════
    public static String contractSent(
        String candidateName,
        String positionName,
        String contractNumber,
        String deadline
    ) {
        String body =
        greeting(candidateName) +
        '<p style="font-size:14px;color:#2c2c2c;line-height:1.7;margin:0 0 20px 0;">' +
        'Congratulations! You have been selected for the following position. ' +
        'Please review the attached contract and sign it before the deadline.' +
        '</p>' +
        infoCard(new List<String[]>{
            new String[]{ 'Position', positionName },
            new String[]{ 'Contract Number', contractNumber },
            new String[]{ 'Signing Deadline', '<span style="color:' + ORANGE + ';font-weight:bold;">' + deadline + '</span>' }
        }) +
        orangeNotice(
            '<strong>Next steps:</strong> Your contract document is attached to this email as a PDF. ' +
            'Please sign and return it before the deadline. ' +
            'Failure to do so will result in automatic cancellation of your offer.'
        ) +
        closing();

        return wrapContent(
            'Your Contract is Ready',
            'Please review and sign your employment contract',
            body
        );
    }

    // ═══════════════════════════════════════════
    // 5. HIRED / WELCOME
    // ═══════════════════════════════════════════
    public static String hired(String candidateName, String positionName, String startDate) {
        String body =
        greeting(candidateName) +
        '<p style="font-size:14px;color:#2c2c2c;line-height:1.7;margin:0 0 20px 0;">' +
        'We are thrilled to welcome you to the <strong>TalentForce Recruit</strong> family! ' +
        'Your contract has been signed and your onboarding is now confirmed.' +
        '</p>' +
        infoCard(new List<String[]>{
            new String[]{ 'Position', positionName },
            new String[]{ 'Start Date', startDate }
        }) +
        orangeNotice(
            'Our team will reach out to you shortly with further onboarding details. ' +
            'We look forward to working with you!'
        ) +
        closing();

        return wrapContent(
            'Welcome to TalentForce!',
            'We are excited to have you on board',
            body
        );
    }

    // ═══════════════════════════════════════════
    // 6. REJECTED
    // ═══════════════════════════════════════════
    public static String rejected(String candidateName, String positionName, String reason) {
        String reasonText = '';
        if (reason == 'no_show') {
            reasonText = 'Following your absence at the scheduled interview, ';
        } else if (reason == 'withdrawn') {
            reasonText = 'Following your withdrawal from the process, ';
        } else if (reason == 'expired') {
            reasonText = 'As the contract signing deadline has passed, ';
        } else {
            reasonText = 'After careful consideration of all applications, ';
        }

        String body =
        greeting(candidateName) +
        '<p style="font-size:14px;color:#2c2c2c;line-height:1.7;margin:0 0 20px 0;">' +
        reasonText +
        'we regret to inform you that your application for the position below will not be moving forward at this time.' +
        '</p>' +
        infoCard(new List<String[]>{
            new String[]{ 'Position', positionName }
        }) +
        '<p style="font-size:14px;color:#2c2c2c;line-height:1.7;margin:0 0 20px 0;">' +
        'We truly appreciate the time and effort you invested in our recruitment process ' +
        'and encourage you to apply for future opportunities that match your profile.' +
        '</p>' +
        closing();

        return wrapContent(
            'Application Update',
            'Thank you for your interest in TalentForce Recruit',
            body
        );
    }
    
    // ═══════════════════════════════════════════
// 7. PORTAL CREDENTIALS
// ═══════════════════════════════════════════
public static String portalCredentials(String candidateName, String candidateEmail, String resetPasswordUrl) {
    String body =
    greeting(candidateName) +
    '<p style="font-size:14px;color:#2c2c2c;line-height:1.7;margin:0 0 20px 0;">' +
    'Your application has been reviewed and approved. ' +
    'You can now access the <strong>TalentForce Recruit</strong> candidate portal ' +
    'to track your application status.' +
    '</p>' +
    infoCard(new List<String[]>{
        new String[]{ 'Username', candidateEmail },
        new String[]{ 'Portal Access', 'TalentForce Candidate Portal' }
    }) +
    orangeNotice(
        'You will receive a separate email with a secure link to set your password . Please check your inbox and spam folder. Once set, use the button below to access the portal.'
    ) +
    '<div style="text-align:center;margin:24px 0;">' +
    '<a href="' + resetPasswordUrl + '" style="background-color:' + BLUE + ';color:#ffffff;padding:14px 32px;text-decoration:none;border-radius:6px;font-weight:bold;font-size:15px;">Set My Password &amp; Login</a>' +
    '</div>' +
    '<p style="font-size:12px;color:#999;text-align:center;">If the button doesn\'t work, copy and paste this link into your browser:<br/>' +
    '<a href="' + resetPasswordUrl + '" style="color:' + BLUE + ';">' + resetPasswordUrl + '</a></p>' +
    closing();

    return wrapContent(
        'Your Portal Access is Ready',
        'Welcome to TalentForce Recruit candidate portal',
        body
    );
}

}