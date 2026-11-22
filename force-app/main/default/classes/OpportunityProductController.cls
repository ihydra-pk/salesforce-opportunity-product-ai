/**
 * Backs the opportunityProductCorrector LWC.
 * Reads the products on an Opportunity and saves corrections to Quantity,
 * Sales Price and Discount. Every changed field is written to
 * Product_Correction_Log__c so the correction can be audited and reported on.
 * All queries and DML run in user mode, so the running user's object, field
 * and sharing permissions are enforced.
 */
public with sharing class OpportunityProductController {
  @TestVisible
  private static final List<String> EDITABLE_FIELDS = new List<String>{
    'Quantity',
    'UnitPrice',
    'Discount'
  };

  @AuraEnabled(cacheable=true)
  public static List<OpportunityLineItem> getLineItems(Id opportunityId) {
    return [
      SELECT
        Id,
        Product2.Name,
        ProductCode,
        Quantity,
        UnitPrice,
        ListPrice,
        Discount,
        TotalPrice
      FROM OpportunityLineItem
      WHERE OpportunityId = :opportunityId
      WITH USER_MODE
      ORDER BY Product2.Name
    ];
  }

  /**
   * Saves the edited values and logs one Product_Correction_Log__c row per changed field.
   * Returns the number of line items that were actually updated.
   */
  @AuraEnabled
  public static Integer saveCorrections(
    List<OpportunityLineItem> drafts,
    String reason
  ) {
    if (drafts == null || drafts.isEmpty()) {
      throw error('There are no changes to save.');
    }
    if (String.isBlank(reason)) {
      throw error('Enter a reason for the correction.');
    }

    Set<Id> lineItemIds = new Set<Id>();
    for (OpportunityLineItem draft : drafts) {
      lineItemIds.add(draft.Id);
    }
    Map<Id, OpportunityLineItem> originals = new Map<Id, OpportunityLineItem>(
      [
        SELECT Id, OpportunityId, Product2.Name, Quantity, UnitPrice, Discount
        FROM OpportunityLineItem
        WHERE Id IN :lineItemIds
        WITH USER_MODE
      ]
    );

    List<OpportunityLineItem> updates = new List<OpportunityLineItem>();
    List<Product_Correction_Log__c> logs = new List<Product_Correction_Log__c>();

    for (OpportunityLineItem draft : drafts) {
      OpportunityLineItem original = originals.get(draft.Id);
      if (original == null) {
        throw error(
          'Opportunity product ' +
            draft.Id +
            ' was not found or you do not have access to it.'
        );
      }

      OpportunityLineItem changed = new OpportunityLineItem(Id = draft.Id);
      Map<String, Object> sentFields = draft.getPopulatedFieldsAsMap();
      for (String field : EDITABLE_FIELDS) {
        if (!sentFields.containsKey(field)) {
          continue;
        }
        Decimal oldValue = (Decimal) original.get(field);
        Decimal newValue = (Decimal) draft.get(field);
        if (oldValue == newValue) {
          continue;
        }
        changed.put(field, newValue);
        logs.add(
          new Product_Correction_Log__c(
            Opportunity__c = original.OpportunityId,
            Line_Item_Id__c = original.Id,
            Product_Name__c = original.Product2.Name,
            Field_Changed__c = field,
            Old_Value__c = oldValue == null ? null : String.valueOf(oldValue),
            New_Value__c = newValue == null ? null : String.valueOf(newValue),
            Reason__c = reason.trim().left(255)
          )
        );
      }
      // Id is always populated, so more than one field means something changed.
      if (changed.getPopulatedFieldsAsMap().size() > 1) {
        updates.add(changed);
      }
    }

    if (updates.isEmpty()) {
      return 0;
    }

    // Line items and their log rows succeed or fail together.
    Savepoint beforeSave = Database.setSavepoint();
    try {
      update as user updates;
      insert as user logs;
    } catch (DmlException e) {
      Database.rollback(beforeSave);
      throw error(e.getDmlMessage(0));
    }
    return updates.size();
  }

  // AuraHandledException hides its message from tests unless setMessage is called.
  private static AuraHandledException error(String message) {
    AuraHandledException e = new AuraHandledException(message);
    e.setMessage(message);
    return e;
  }
}
