/**
 * Runs the Opportunity_Product_Health_Review prompt template for the
 * AI Review button of the opportunityProductCorrector LWC.
 */
public with sharing class ProductHealthAIController {
  @TestVisible
  private static final String TEMPLATE_NAME = 'Opportunity_Product_Health_Review';

  // Generative AI calls aren't allowed in Apex tests, so tests set these instead.
  @TestVisible
  private static String testResponse;
  @TestVisible
  private static Exception testException;

  @AuraEnabled
  public static String reviewProducts(Id opportunityId) {
    try {
      return generate(buildInput(opportunityId));
    } catch (Exception e) {
      String message = 'AI review failed: ' + e.getMessage();
      AuraHandledException error = new AuraHandledException(message);
      error.setMessage(message);
      throw error;
    }
  }

  // The template's input is named myOpportunity, so the key is Input:myOpportunity.
  @TestVisible
  private static ConnectApi.EinsteinPromptTemplateGenerationsInput buildInput(
    Id opportunityId
  ) {
    ConnectApi.WrappedValue opportunity = new ConnectApi.WrappedValue();
    opportunity.value = new Map<String, String>{ 'id' => opportunityId };

    ConnectApi.EinsteinPromptTemplateGenerationsInput input = new ConnectApi.EinsteinPromptTemplateGenerationsInput();
    input.isPreview = false;
    input.inputParams = new Map<String, ConnectApi.WrappedValue>{
      'Input:myOpportunity' => opportunity
    };
    input.additionalConfig = new ConnectApi.EinsteinLlmAdditionalConfigInput();
    input.additionalConfig.applicationName = 'PromptBuilderPreview';
    return input;
  }

  private static String generate(
    ConnectApi.EinsteinPromptTemplateGenerationsInput input
  ) {
    if (Test.isRunningTest()) {
      if (testException != null) {
        throw testException;
      }
      return testResponse;
    }
    ConnectApi.EinsteinPromptTemplateGenerationsRepresentation result = ConnectApi.EinsteinLLM.generateMessagesForPromptTemplate(
      TEMPLATE_NAME,
      input
    );
    return result.generations[0].text;
  }
}
