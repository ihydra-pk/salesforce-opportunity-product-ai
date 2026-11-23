@IsTest
private class ProductHealthTest {
  @TestSetup
  static void setup() {
    System.runAs(testUser()) {
      PermissionSet access = [
        SELECT Id
        FROM PermissionSet
        WHERE Name = 'Product_Correction_Access'
      ];
      if (
        [
          SELECT COUNT()
          FROM PermissionSetAssignment
          WHERE
            AssigneeId = :UserInfo.getUserId()
            AND PermissionSetId = :access.Id
        ] == 0
      ) {
        insert new PermissionSetAssignment(
          AssigneeId = UserInfo.getUserId(),
          PermissionSetId = access.Id
        );
      }
    }

    List<Product2> products = new List<Product2>{
      new Product2(Name = 'A Overpriced', ProductCode = 'A', IsActive = true),
      new Product2(Name = 'B Discounted', ProductCode = 'B', IsActive = true),
      new Product2(Name = 'C Healthy', ProductCode = 'C', IsActive = true)
    };
    insert products;
    List<PricebookEntry> entries = new List<PricebookEntry>();
    for (Product2 product : products) {
      entries.add(
        new PricebookEntry(
          Pricebook2Id = Test.getStandardPricebookId(),
          Product2Id = product.Id,
          UnitPrice = 100,
          IsActive = true
        )
      );
    }
    insert entries;
    Opportunity opp = new Opportunity(
      Name = 'Health Check Opp',
      StageName = 'Prospecting',
      CloseDate = Date.today().addDays(30),
      Pricebook2Id = Test.getStandardPricebookId()
    );
    insert opp;
    insert new List<OpportunityLineItem>{
      new OpportunityLineItem(
        OpportunityId = opp.Id,
        PricebookEntryId = entries[0].Id,
        Quantity = 1,
        UnitPrice = 150
      ),
      new OpportunityLineItem(
        OpportunityId = opp.Id,
        PricebookEntryId = entries[1].Id,
        Quantity = 1,
        UnitPrice = 100,
        Discount = 30
      ),
      new OpportunityLineItem(
        OpportunityId = opp.Id,
        PricebookEntryId = entries[2].Id,
        Quantity = 1,
        UnitPrice = 95
      )
    };
  }

  private static User testUser() {
    return new User(Id = UserInfo.getUserId());
  }

  @IsTest
  static void flagsPricingProblems() {
    Assert.areEqual(
      new List<String>{ 'sales price is 50% above list price' },
      ProductHealthGrounding.flagsFor(1, 150, 100, null)
    );
    Assert.areEqual(
      new List<String>{ 'sales price is 40% below list price' },
      ProductHealthGrounding.flagsFor(1, 60, 100, null)
    );
    Assert.areEqual(
      new List<String>{ 'discount 25% is above the 20% review threshold' },
      ProductHealthGrounding.flagsFor(1, 100, 100, 25)
    );
    Assert.areEqual(
      new List<String>{
        'large volume at full list price, check volume pricing'
      },
      ProductHealthGrounding.flagsFor(5000, 100, 100, null)
    );
  }

  @IsTest
  static void healthyLineHasNoFlags() {
    Assert.isTrue(ProductHealthGrounding.flagsFor(10, 95, 100, 5).isEmpty());
  }

  @IsTest
  static void groundingDescribesEveryProductWithFlags() {
    System.runAs(testUser()) {
      ProductHealthGrounding.Request request = new ProductHealthGrounding.Request();
      request.myOpportunity = [SELECT Id FROM Opportunity LIMIT 1];

      Test.startTest();
      String facts = ProductHealthGrounding.getFacts(
          new List<ProductHealthGrounding.Request>{ request }
        )[0]
        .Prompt;
      Test.stopTest();

      Assert.isTrue(facts.contains('Opportunity: Health Check Opp'), facts);
      Assert.isTrue(
        facts.contains('A Overpriced (A)') &&
        facts.contains('50% above list price'),
        facts
      );
      Assert.isTrue(
        facts.contains('B Discounted (B)') &&
        facts.contains('above the 20% review threshold'),
        facts
      );
      Assert.isTrue(
        facts.contains('C Healthy (C)') && facts.contains('Flags: none'),
        facts
      );
    }
  }

  @IsTest
  static void controllerReturnsTheGeneratedReview() {
    ProductHealthAIController.testResponse = 'Review the 50% markup on A Overpriced.';
    Id oppId = [SELECT Id FROM Opportunity LIMIT 1].Id;

    Assert.areEqual(
      'Review the 50% markup on A Overpriced.',
      ProductHealthAIController.reviewProducts(oppId)
    );
  }

  @IsTest
  static void controllerSendsOpportunityAsTemplateInput() {
    Id oppId = [SELECT Id FROM Opportunity LIMIT 1].Id;

    ConnectApi.EinsteinPromptTemplateGenerationsInput input = ProductHealthAIController.buildInput(
      oppId
    );

    Map<String, String> value = (Map<String, String>) input.inputParams.get(
        'Input:myOpportunity'
      )
      .value;
    Assert.areEqual(oppId, value.get('id'));
    Assert.isFalse(input.isPreview);
  }

  @IsTest
  static void controllerReportsAiErrors() {
    ProductHealthAIController.testException = new CalloutException(
      'Model unavailable'
    );
    Id oppId = [SELECT Id FROM Opportunity LIMIT 1].Id;

    try {
      ProductHealthAIController.reviewProducts(oppId);
      Assert.fail('The AI error should reach the user');
    } catch (AuraHandledException e) {
      Assert.areEqual('AI review failed: Model unavailable', e.getMessage());
    }
  }
}
