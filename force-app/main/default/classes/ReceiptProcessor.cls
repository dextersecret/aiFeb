public class ReceiptProcessor {
    @AuraEnabled
    public static String processReceipt(Id contentDocumentId) {
        // Fetch the image
        ContentVersion cv = [SELECT VersionData FROM ContentVersion WHERE ContentDocumentId = :contentDocumentId AND IsLatest = true LIMIT 1];
        Blob receiptImage = cv.VersionData;

        // Google Vision API setup
        String apiKey = 'YOUR_GOOGLE_API_KEY'; // Store securely in Named Credentials or Custom Settings
        HttpRequest req = new HttpRequest();
        req.setEndpoint('https://vision.googleapis.com/v1/images:annotate?key=' + apiKey);
        req.setMethod('POST');
        req.setHeader('Content-Type', 'application/json');

        // Build request body
        String body = JSON.serialize(new Map<String, Object>{
            'requests' => new List<Object>{
                new Map<String, Object>{
                    'image' => new Map<String, String>{
                        'content' => EncodingUtil.base64Encode(receiptImage)
                    },
                    'features' => new List<Object>{
                        new Map<String, String>{
                            'type' => 'TEXT_DETECTION'
                        }
                    }
                }
            }
        });
        req.setBody(body);

        // Send request
        Http http = new Http();
        HttpResponse res = http.send(req);
        if (res.getStatusCode() == 200) {
            return parseVisionResponse(res.getBody());
        } else {
            throw new AuraHandledException('Google Vision Error: ' + res.getStatus());
        }
    }

    private static String parseVisionResponse(String jsonResponse) {
        Map<String, Object> response = (Map<String, Object>) JSON.deserializeUntyped(jsonResponse);
        List<Object> annotations = (List<Object>) ((Map<String, Object>) ((List<Object>) response.get('responses')).get(0)).get('textAnnotations');
        
        // Simple parsing logic (assumes line items are in format "ItemName Price")
        List<Map<String, Object>> lineItems = new List<Map<String, Object>>();
        String fullText = (String) ((Map<String, Object>) annotations.get(0)).get('description');
        List<String> lines = fullText.split('\n');
        
        for (String line : lines) {
            List<String> parts = line.trim().split('\\s+');
            if (parts.size() >= 2 && Pattern.matches('^\\$?\\d+\\.\\d{2}$', parts[parts.size() - 1])) {
                String price = parts[parts.size() - 1].replace('$', '');
                String name = '';
                for (Integer i = 0; i < parts.size() - 1; i++) {
                    name += parts[i] + ' ';
                }
                lineItems.add(new Map<String, Object>{
                    'name' => name,
                    'price' => Decimal.valueOf(price)
                });
            }
        }

        Map<String, Object> result = new Map<String, Object>{
            'lineItems' => lineItems
        };
        return JSON.serialize(result);
    }
}