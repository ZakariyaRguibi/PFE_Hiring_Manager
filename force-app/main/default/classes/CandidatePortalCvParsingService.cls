public without sharing class CandidatePortalCvParsingService {
  public class ParsedCvDTO {
    @AuraEnabled
    public String extractedSkills;
    @AuraEnabled
    public String extractedKeywords;
    @AuraEnabled
    public String extractedEducation;
    @AuraEnabled
    public Integer extractedExperience;
    @AuraEnabled
    public String rawResponse;
  }

  @AuraEnabled
  public static ParsedCvDTO parseCv(Id contentDocumentId) {
    if (contentDocumentId == null) {
      throw new AuraHandledException('CV file is required.');
    }

    String rawResponse = invokeCvParser(contentDocumentId);
    return parsePromptResponse(rawResponse);
  }

  private static String invokeCvParser(Id contentDocumentId) {
    ConnectApi.EinsteinPromptTemplateGenerationsInput promptInput = new ConnectApi.EinsteinPromptTemplateGenerationsInput();

    promptInput.isPreview = false;
    promptInput.additionalConfig = new ConnectApi.EinsteinLlmAdditionalConfigInput();
    promptInput.additionalConfig.applicationName = 'PromptBuilderPreview';
    promptInput.additionalConfig.numGenerations = 1;

    Map<String, ConnectApi.WrappedValue> inputParams = new Map<String, ConnectApi.WrappedValue>();

    Map<String, String> cvInput = new Map<String, String>();
    cvInput.put('id', String.valueOf(contentDocumentId));

    ConnectApi.WrappedValue cvWrappedValue = new ConnectApi.WrappedValue();
    cvWrappedValue.value = cvInput;

    inputParams.put('Input:CV', cvWrappedValue);

    promptInput.inputParams = inputParams;

    ConnectApi.EinsteinPromptTemplateGenerationsRepresentation response = ConnectApi.EinsteinLLM.generateMessagesForPromptTemplate(
      'CV_Parser',
      promptInput
    );

    if (
      response == null ||
      response.generations == null ||
      response.generations.isEmpty()
    ) {
      throw new AuraHandledException('CV parser returned no response.');
    }

    return response.generations[0].text;
  }

  private static ParsedCvDTO parsePromptResponse(String rawResponse) {
    if (String.isBlank(rawResponse)) {
      throw new AuraHandledException('CV parser returned an empty response.');
    }

    String cleaned = rawResponse.trim();

    if (cleaned.startsWith('```')) {
      cleaned = cleaned.replace('```json', '');
      cleaned = cleaned.replace('```', '');
      cleaned = cleaned.trim();
    }

    Map<String, Object> parsed;

    try {
      parsed = (Map<String, Object>) JSON.deserializeUntyped(cleaned);
    } catch (Exception e) {
      throw new AuraHandledException(
        'CV parser returned invalid JSON: ' + cleaned
      );
    }

    ParsedCvDTO dto = new ParsedCvDTO();
    dto.rawResponse = cleaned;
    dto.extractedSkills = getStringValue(parsed, 'Extracted_Skills');
    dto.extractedKeywords = getStringValue(parsed, 'Extracted_Keywords');
    dto.extractedEducation = getStringValue(parsed, 'Extracted_Education');
    dto.extractedExperience = getIntegerValue(parsed, 'Extracted_Experience');

    return dto;
  }

  private static String getStringValue(Map<String, Object> parsed, String key) {
    if (!parsed.containsKey(key) || parsed.get(key) == null) {
      return null;
    }

    return String.valueOf(parsed.get(key));
  }

  private static Integer getIntegerValue(
    Map<String, Object> parsed,
    String key
  ) {
    if (!parsed.containsKey(key) || parsed.get(key) == null) {
      return null;
    }

    Object value = parsed.get(key);

    if (value instanceof Integer) {
      return (Integer) value;
    }

    if (value instanceof Long) {
      return Integer.valueOf(String.valueOf(value));
    }

    if (value instanceof Decimal) {
      return ((Decimal) value).intValue();
    }

    return Integer.valueOf(String.valueOf(value));
  }
}
