public class EmailToApp implements Messaging.InboundEmailHandler {
   
    public Messaging.InboundEmailResult handleInboundEmail(Messaging.InboundEmail email, Messaging.InboundEnvelope envelope) {
       Messaging.InboundEmailResult result = new Messaging.InboundEmailResult();
      String inReplyTo;
        // Extract the In-Reply-To header
        for (Messaging.InboundEmail.Header header : email.headers) {
            if (header.name == 'In-Reply-To') {
                inReplyTo = header.value;
                break;
            }
        }

        System.debug('In-Reply-To header: ' + inReplyTo);
        EmailMessage emailMsgRecord = new EmailMessage();
        emailMsgRecord = [SELECT Id, RelatedToId FROM EmailMessage WHERE MessageIdentifier = :inReplyTo LIMIT 1];
        
        Id appId = emailMsgRecord?.RelatedToId;

         List<App__c> appRecord = new List<App__c>();
        appRecord = [SELECT Id, Name, OwnerId FROM App__c WHERE Id = :appId ];
       
        
        EmailMessage appEmailMessage = createEmailMessage(email, appRecord);

        // Insert the EmailMessage record if accessible
        if (Schema.sObjectType.EmailMessage.isAccessible() && Schema.sObjectType.EmailMessage.isCreateable()) {
            insert appEmailMessage;
        }

       // Attach the binary attachment to the Files related list and link to EmailMessage
        if (email.binaryAttachments != null) {
            Messaging.InboundEmail.BinaryAttachment[] attachments = email.binaryAttachments;
            for (Messaging.InboundEmail.BinaryAttachment attachment : attachments) {
                Blob bodyAttachment = attachment.body;
                String attachmentName = attachment.fileName;
                ContentVersion cv = new ContentVersion();
                cv.VersionData = bodyAttachment;
                cv.Title = attachmentName;
                cv.PathOnClient = attachmentName;
                insert cv;

                // Link the attachment to the App__c record
                ContentDocumentLink contentDocumentLinkApp = new ContentDocumentLink();
                contentDocumentLinkApp.ContentDocumentId = [SELECT ContentDocumentId FROM ContentVersion WHERE Id = :cv.Id].ContentDocumentId;
                contentDocumentLinkApp.LinkedEntityId = appRecord.Id;  
                contentDocumentLinkApp.ShareType = 'I';  // 'I' means Inferred permission (default for internal users)
                contentDocumentLinkApp.Visibility = 'AllUsers';
                insert contentDocumentLinkApp;

                // Link the attachment to the EmailMessage record
                ContentDocumentLink contentDocumentLinkEmail = new ContentDocumentLink();
                contentDocumentLinkEmail.ContentDocumentId = contentDocumentLinkApp.ContentDocumentId;
                contentDocumentLinkEmail.LinkedEntityId = appEmailMessage.Id;  
                contentDocumentLinkEmail.ShareType = 'I';  // 'I' means Inferred permission (default for internal users)
                contentDocumentLinkEmail.Visibility = 'AllUsers';
                insert contentDocumentLinkEmail;
            }
        }

        // Add Email Message Relation for the sender's address
        EmailMessageRelation emr = new EmailMessageRelation();
        emr.EmailMessageId = appEmailMessage.Id;
        emr.RelationAddress = email.fromAddress;
        emr.RelationType = 'FromAddress';
        if (Schema.sObjectType.EmailMessageRelation.isAccessible() && Schema.sObjectType.EmailMessageRelation.isCreateable()) {
            insert emr;
        }

        result.success = true;
        return result;
    }
    public EmailMessage createEmailMessage(Messaging.InboundEmail email, App__c appRecord) {
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
        appEmailMessage.RelatedToId = 'appRecord.Id';
        appEmailMessage.MessageIdentifier = email.messageId;
        return appEmailMessage;
    }
}
