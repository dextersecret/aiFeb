public class ReceiptProcessor {
    @AuraEnabled
    public static String processReceipt(Id contentDocumentId) {
        // Fetch the image
        ContentVersion cv = [SELECT VersionData FROM ContentVersion WHERE ContentDocumentId = :contentDocumentId AND IsLatest = true LIMIT 1];
        Blob receiptImage = cv.VersionData;

        // xAI Grok Vision API setup
        String apiKey = ''; // Store securely in Named Credentials or Custom Settings
        HttpRequest req = new HttpRequest();
        req.setEndpoint('https://api.x.ai/v1/chat/completions'); // xAI's REST endpoint
        req.setMethod('POST');
        req.setHeader('Authorization', 'Bearer ' + apiKey);
        req.setHeader('Content-Type', 'application/json');

        // Build request body with image and prompt
        String base64Image = EncodingUtil.base64Encode(receiptImage);
        String prompt = 'Extract the line items and prices from this receipt image. Return *only* a JSON array of objects, each with name and price fields (e.g., [{name: Milk, price: 5.99}, {name: Bread, price: 2.99}]). Do not include any additional text or explanations before or after the JSON array. If no items are found, return an empty array.';


        String image_url = 'https://science.nasa.gov/wp-content/uploads/2023/09/web-first-images-release.png';

        String body = '{' +
            '"model": "grok-2-vision-latest",' +
            '"messages": [' +
                '{' +
                    '"role": "user",' +
                    '"content": [' +
                        '{' +
                            '"type": "image_url",' +
                            '"image_url": {' +
                                '"url": "data:image/jpeg;base64,'+base64Image+'",' +
                                '"detail": "high"' +
                            '}' +
                        '},' +
                        '{' +
                            '"type": "text",' +
                            '"text": "'+ prompt +'"' +
                        '}' +
                    ']' +
                '}' +
            ']' +
        '}';


        req.setBody(body);


        // Send request
        Http http = new Http();
        HttpResponse res = http.send(req);
        if (res.getStatusCode() == 200) {
            
            System.debug(':::RAW RESPONSE: '+ res.getBody());
            
            return parseGrokResponse(res.getBody());
        } else {
            throw new AuraHandledException('Xai Vision Error: ' + res.getStatus());
        }
    }

    private static String parseGrokResponse(String jsonResponse) {
        Map<String, Object> response = (Map<String, Object>) JSON.deserializeUntyped(jsonResponse);
        List<Object> choices = (List<Object>) response.get('choices');
        if (choices == null || choices.isEmpty()) {
            throw new AuraHandledException('No response from Grok Vision API');
        }

        Map<String, Object> choice = (Map<String, Object>) choices[0];
        Map<String, Object> message = (Map<String, Object>) choice.get('message');
        String content = (String) message.get('content');

        // Parse the content as a JSON array directly
        List<Object> lineItems;
        try {
            // Expecting content to be a pure JSON array like [{"name": "Milk", "price": 5.99}, ...]
            lineItems = (List<Object>) JSON.deserializeUntyped(content);
        } catch (Exception e) {
            // Fallback if Grok still adds text: extract JSON array with regex
            String jsonArray = extractJsonArray(content);
            if (String.isNotBlank(jsonArray)) {
                lineItems = (List<Object>) JSON.deserializeUntyped(jsonArray);
            } else {
                throw new AuraHandledException('Failed to parse Grok response as JSON array: ' + content);
            }
        }

        Map<String, Object> result = new Map<String, Object>{
            'lineItems' => lineItems
        };
        return JSON.serialize(result);
    }

    // Helper method to extract JSON array from response if preceded by text
    private static String extractJsonArray(String content) {
        // Match the first occurrence of a JSON array (e.g., "[{...}]")
        Pattern p = Pattern.compile('\\[\\s*\\{.*?\\}\\s*(?:,\\s*\\{.*?\\}\\s*)*\\]');
        Matcher m = p.matcher(content);
        if (m.find()) {
            return m.group(0);
        }
        return null;
    }
}