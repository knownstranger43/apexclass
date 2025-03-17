/*global with sharing class PackAdminEmailClass implements Messaging.InboundEmailHandler {
    public Messaging.InboundEmailResult handleInboundEmail(Messaging.InboundEmail email, Messaging.InboundEnvelope envelope) {
        Messaging.InboundEmailResult result = new Messaging.InboundEmailresult();
        
        System.debug('Email Subject Line: ' + email.subject);
        System.debug('Email From: ' + email.fromname);
        
        EmailMessage upEmail = [SELECT RelatedtoId, FromId, FromName, FromAddress, ToAddress, CcAddress, MessageDate, TextBody,
                                Forecast_Change__c, ReplyToEmailMessageId, Id,HtmlBody, Pack_Change__c, IsExternallyVisible
                                FROM EmailMessage WHERE ReplyToEmailMessageId =: email.inReplyTo ORDER BY MessageDate DESC LIMIT 1];
        System.debug('upEmail: ' + upEmail);
        System.debug('RelatedToId: ' + upEmail.RelatedToId + ' Type: ' + String.valueOf(upEmail.RelatedToId.getSObjectType()));

        
        //try{
            System.debug('in-Reply-To token? ' + email.inReplyTo);        
            
            // New EmailMessage object to be created        
            EmailMessage emailAdd = new EmailMessage(Status = '0',
                                                     MessageIdentifier = email.inReplyTo, 
                                                   //  ParentId = upEmail.RelatedToId,
                                                     Pack_Change__c = upEmail.Pack_Change__c,
                                                     FromAddress = email.fromAddress,
                                                     FromName = email.fromName,
                                                     TextBody = email.plainTextBody,
                                                     HtmlBody = email.htmlBody,
                                                     Subject = email.subject//,
                                                     //ClientThreadIdentifier = getClientThreadIdentifier(email.headers)
                                                     );  
            if(email.ccAddresses != NULL){
                emailAdd.CcAddress = String.join(email.ccAddresses,';');
            }
            if(email.toAddresses != NULL){
                emailAdd.ToAddress = String.join(email.toAddresses,';');                
            }
         // Retrieve the original email body and append it to the new reply body
    if (upEmail.HtmlBody != null) {
        // Append the original email content
        emailAdd.HtmlBody = upEmail.HtmlBody + '<br/><br/>-----Original Message-----<br/>' + email.htmlBody;
        emailAdd.TextBody = upEmail.TextBody + '\n\n-----Original Message-----\n' + email.plainTextBody; // Similar for text body
    }
            
            insert emailAdd;
            
            System.debug('New Email Message: ' + emailAdd ); 
            
       
        return result;
    }
    
    //private String getClientThreadIdentifier(List<Messaging.InboundEmail.Header> headers) {
    //    if (headers == null || headers.size() == 0) return null;
    //    try {
    //        for (Messaging.InboundEmail.Header header : headers) {
    //            if (header.name.equalsIgnoreCase('thread-index')) {
    //                Blob threadIndex = EncodingUtil.base64Decode(header.value.trim());
    //                return EncodingUtil.convertToHex(threadIndex).substring(0, 44).toUpperCase();
    //            }
    //        }
    //    } catch (Exception e){
    //        return null;
    //    }
    //    return null;
    //}
}*/

public with sharing class PackAdminEmailClass implements Messaging.InboundEmailHandler {

    public Messaging.InboundEmailResult handleInboundEmail(Messaging.InboundEmail email, Messaging.InboundEnvelope envelope) {
        System.debug('Incoming email processing started');
        string esubject = (string)email.subject;
        
        Messaging.InboundEmailResult result = new Messaging.InboundEmailResult();
        String inReplyTo = '';
        Id packchangeId;
        List<Pack_Changes__c> packChangeList = new List<Pack_Changes__c>();
        List<EmailMessage> emailMsgList = new List<EmailMessage>();
        EmailMessage appEmailMessage = new EmailMessage();
         // Extract the In-Reply-To header
        System.debug('Extracting In-Reply-To header');
        for (Messaging.InboundEmail.Header header : email.headers) {
            if (header.name == 'In-Reply-To') {
                inReplyTo = header.value;
                break;
            }
        }
        System.debug('In-Reply-To header value: ' + inReplyTo);

        if (inReplyTo != '') {
            System.debug('Fetching related email message');
            
            emailMsgList = [SELECT Id, RelatedToId FROM EmailMessage WHERE MessageIdentifier = :inReplyTo LIMIT 1];
            
             System.debug('Fetching  emailMsgList'+emailMsgList);
            if (!emailMsgList.isEmpty()) {
                packchangeId = emailMsgList[0].RelatedToId;
                System.debug('Found related Pack_Changes__c Id: ' + packchangeId);
            }
            
            if (packchangeId != null) {
                packChangeList = [SELECT Id, Name FROM Pack_Changes__c WHERE Id = :packchangeId LIMIT 1];
            }
        }
       
        if (!packChangeList.isEmpty() || esubject.contains('Forwarding Confirmation')) {
            System.debug('Creating EmailMessage record');
            appEmailMessage = createEmailMessage(email, packChangeList.isEmpty() ? null : packChangeList[0]);
            insert appEmailMessage;
            System.debug('EmailMessage inserted with Id: ' + appEmailMessage.Id);

            EmailMessageRelation emr = new EmailMessageRelation();
            emr.EmailMessageId = appEmailMessage.Id;
            emr.RelationAddress = email.fromAddress;
            emr.RelationType = 'FromAddress';
            insert emr;
            System.debug('EmailMessageRelation inserted');
        }
        
          // Attach the binary attachment to the Files related list and link to EmailMessage
        if (email.binaryAttachments != null && appEmailMessage.Id != null && !packChangeList.isEmpty()) {
            System.debug('Processing attachments');
            for (Messaging.InboundEmail.BinaryAttachment attachment : email.binaryAttachments) {
                System.debug('Processing attachment: ' + attachment.fileName);
                Blob bodyAttachment = attachment.body;
                String attachmentName = attachment.fileName;

                ContentVersion cv = new ContentVersion();
                cv.VersionData = bodyAttachment;
                cv.Title = attachmentName;
                cv.PathOnClient = attachmentName;
                insert cv;
                System.debug('ContentVersion inserted with Id: ' + cv.Id);
                ContentDocumentLink contentDocumentLinkApp = new ContentDocumentLink();
                contentDocumentLinkApp.ContentDocumentId = [SELECT ContentDocumentId FROM ContentVersion WHERE Id = :cv.Id].ContentDocumentId;
                contentDocumentLinkApp.LinkedEntityId = packChangeId;  
                contentDocumentLinkApp.ShareType = 'I';
                contentDocumentLinkApp.Visibility = 'AllUsers';
                  // Link the attachment to the App__c record
                insert contentDocumentLinkApp;
                System.debug('ContentDocumentLink created for Pack_Changes__c');

                ContentDocumentLink contentDocumentLinkEmail = new ContentDocumentLink();
                contentDocumentLinkEmail.ContentDocumentId = contentDocumentLinkApp.ContentDocumentId;
                contentDocumentLinkEmail.LinkedEntityId = appEmailMessage.Id;  
                contentDocumentLinkEmail.ShareType = 'I';  // 'I' means Inferred permission (default for internal users)
                contentDocumentLinkEmail.Visibility = 'AllUsers';
                insert contentDocumentLinkEmail;
                System.debug('ContentDocumentLink created for EmailMessage');
            }
        }
        
        System.debug('Email processing completed successfully');
        result.success = true;
        return result;
    }

    public EmailMessage createEmailMessage(Messaging.InboundEmail email, Pack_Changes__c packChangeRecord) {
        System.debug('Creating EmailMessage object');
        EmailMessage appEmailMessage = new EmailMessage();
        appEmailMessage.ToAddress = String.join(email.toAddresses, ',');
        if (email.ccAddresses != null) {
            appEmailMessage.CcAddress = String.join(email.ccAddresses, ',');
        }
        appEmailMessage.FromAddress = email.fromAddress;
        appEmailMessage.FromName = email.fromName;
        appEmailMessage.Subject = email.subject;
        appEmailMessage.Status = '2'; // Status '2' indicates that the email was received
        appEmailMessage.HtmlBody = email.htmlBody;
        appEmailMessage.Incoming = true;
        appEmailMessage.TextBody = email.plainTextBody;
        appEmailMessage.RelatedToId = packChangeRecord?.Id;
        appEmailMessage.MessageIdentifier = email.messageId;
        System.debug('EmailMessage object created successfully');
        return appEmailMessage;
    }
}
