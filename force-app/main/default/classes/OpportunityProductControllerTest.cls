@IsTest
private class OpportunityProductControllerTest {
  @TestSetup
  static void setup() {
    // The controller runs in user mode, so the test user needs the same
    // permission set real users get (it grants Discount and the log fields).
    // Setup-object DML runs inside runAs to avoid a mixed-DML error.
    System.runAs(testUser()) {
      PermissionSet access = [
        SELECT Id
        FROM PermissionSet
        WHERE Name = 'Product_Correction_Access'
      ];
      // Tests can see real assignments, so skip if the user already has it.
      Boolean alreadyAssigned =
        [
          SELECT COUNT()
          FROM PermissionSetAssignment
          WHERE
            AssigneeId = :UserInfo.getUserId()
            AND PermissionSetId = :access.Id
        ] > 0;
      if (!alreadyAssigned) {
        insert new PermissionSetAssignment(
          AssigneeId = UserInfo.getUserId(),
          PermissionSetId = access.Id
        );
      }
    }

    Product2 product = new Product2(
      Name = 'eSIM Connectivity Plan',
      ProductCode = 'ESIM-01',
      IsActive = true
    );
    insert product;
    PricebookEntry entry = new PricebookEntry(
      Pricebook2Id = Test.getStandardPricebookId(),
      Product2Id = product.Id,
      UnitPrice = 100,
      IsActive = true
    );
    insert entry;
    Opportunity opp = new Opportunity(
      Name = 'Test Opportunity',
      StageName = 'Prospecting',
      CloseDate = Date.today().addDays(30),
      Pricebook2Id = Test.getStandardPricebookId()
    );
    insert opp;
    insert new OpportunityLineItem(
      OpportunityId = opp.Id,
      PricebookEntryId = entry.Id,
      Quantity = 10,
      UnitPrice = 100
    );
  }

  // Running inside runAs makes the permission set assignment take effect.
  private static User testUser() {
    return new User(Id = UserInfo.getUserId());
  }

  private static OpportunityLineItem lineItem() {
    return [
      SELECT Id, OpportunityId, Quantity, UnitPrice, Discount
      FROM OpportunityLineItem
      LIMIT 1
    ];
  }

  @IsTest
  static void getLineItemsReturnsProductsOfOpportunity() {
    System.runAs(testUser()) {
      Id oppId = lineItem().OpportunityId;

      Test.startTest();
      List<OpportunityLineItem> items = OpportunityProductController.getLineItems(
        oppId
      );
      Test.stopTest();

      Assert.areEqual(1, items.size(), 'The opportunity has one product');
      Assert.areEqual('eSIM Connectivity Plan', items[0].Product2.Name);
    }
  }

  @IsTest
  static void saveCorrectionsUpdatesLineItemAndLogsEachChangedField() {
    System.runAs(testUser()) {
      OpportunityLineItem item = lineItem();
      OpportunityLineItem draft = new OpportunityLineItem(
        Id = item.Id,
        Quantity = 12,
        Discount = 10
      );

      Test.startTest();
      Integer updated = OpportunityProductController.saveCorrections(
        new List<OpportunityLineItem>{ draft },
        'Customer ordered 2 more units'
      );
      Test.stopTest();

      Assert.areEqual(1, updated, 'One line item should be updated');
      OpportunityLineItem saved = lineItem();
      Assert.isTrue(saved.Quantity == 12, 'Quantity: ' + saved.Quantity);
      Assert.isTrue(saved.Discount == 10, 'Discount: ' + saved.Discount);

      // Picklists sort in their defined order, not alphabetically,
      // so look the log rows up by field name instead of by position.
      Map<String, Product_Correction_Log__c> logByField = new Map<String, Product_Correction_Log__c>();
      for (Product_Correction_Log__c log : [
        SELECT
          Field_Changed__c,
          Old_Value__c,
          New_Value__c,
          Reason__c,
          Opportunity__c,
          Product_Name__c
        FROM Product_Correction_Log__c
      ]) {
        logByField.put(log.Field_Changed__c, log);
      }
      Assert.areEqual(
        new Set<String>{ 'Quantity', 'Discount' },
        logByField.keySet(),
        'One log row per changed field; Sales Price was not changed'
      );

      Product_Correction_Log__c discountLog = logByField.get('Discount');
      Assert.isNull(discountLog.Old_Value__c, 'There was no discount before');

      Product_Correction_Log__c quantityLog = logByField.get('Quantity');
      Assert.isTrue(
        Decimal.valueOf(quantityLog.Old_Value__c) == 10,
        'Old value: ' + quantityLog.Old_Value__c
      );
      Assert.isTrue(
        Decimal.valueOf(quantityLog.New_Value__c) == 12,
        'New value: ' + quantityLog.New_Value__c
      );
      Assert.areEqual(item.OpportunityId, quantityLog.Opportunity__c);
      Assert.areEqual('eSIM Connectivity Plan', quantityLog.Product_Name__c);
      Assert.areEqual('Customer ordered 2 more units', quantityLog.Reason__c);
    }
  }

  @IsTest
  static void saveCorrectionsSkipsUnchangedValues() {
    System.runAs(testUser()) {
      OpportunityLineItem item = lineItem();
      OpportunityLineItem draft = new OpportunityLineItem(
        Id = item.Id,
        Quantity = item.Quantity,
        UnitPrice = item.UnitPrice
      );

      Integer updated = OpportunityProductController.saveCorrections(
        new List<OpportunityLineItem>{ draft },
        'No real change'
      );

      Assert.areEqual(0, updated);
      Assert.areEqual(0, [SELECT COUNT() FROM Product_Correction_Log__c]);
    }
  }

  @IsTest
  static void saveCorrectionsRequiresReason() {
    System.runAs(testUser()) {
      OpportunityLineItem draft = new OpportunityLineItem(
        Id = lineItem().Id,
        Quantity = 5
      );
      try {
        OpportunityProductController.saveCorrections(
          new List<OpportunityLineItem>{ draft },
          '  '
        );
        Assert.fail('A blank reason should be rejected');
      } catch (AuraHandledException e) {
        Assert.areEqual('Enter a reason for the correction.', e.getMessage());
      }
    }
  }

  @IsTest
  static void saveCorrectionsRequiresChanges() {
    System.runAs(testUser()) {
      try {
        OpportunityProductController.saveCorrections(
          new List<OpportunityLineItem>(),
          'Reason'
        );
        Assert.fail('An empty list should be rejected');
      } catch (AuraHandledException e) {
        Assert.areEqual('There are no changes to save.', e.getMessage());
      }
    }
  }

  @IsTest
  static void saveCorrectionsRollsBackWhenValidationRuleFails() {
    System.runAs(testUser()) {
      OpportunityLineItem item = lineItem();
      OpportunityLineItem draft = new OpportunityLineItem(
        Id = item.Id,
        Quantity = 20,
        Discount = 60
      );

      try {
        OpportunityProductController.saveCorrections(
          new List<OpportunityLineItem>{ draft },
          'Big discount'
        );
        Assert.fail(
          'A discount over 50% should be blocked by the validation rule'
        );
      } catch (AuraHandledException e) {
        Assert.isTrue(
          e.getMessage().contains('cannot exceed 50%'),
          'Validation rule message is passed to the user: ' + e.getMessage()
        );
      }

      Assert.isTrue(lineItem().Quantity == 10, 'Nothing should be saved');
      Assert.areEqual(
        0,
        [SELECT COUNT() FROM Product_Correction_Log__c],
        'No log rows should remain'
      );
    }
  }
}
