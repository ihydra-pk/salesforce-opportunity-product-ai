// Demo data: one opportunity with three products.
// Run with: sf apex run --file scripts/apex/seed.apex
Pricebook2 standard = [
  SELECT Id, IsActive
  FROM Pricebook2
  WHERE IsStandard = TRUE
  LIMIT 1
];
if (!standard.IsActive) {
  standard.IsActive = true;
  update standard;
}

List<Product2> products = new List<Product2>{
  new Product2(
    Name = 'eSIM Connectivity Plan',
    ProductCode = 'ESIM-01',
    IsActive = true
  ),
  new Product2(
    Name = 'IoT SIM Card (Industrial)',
    ProductCode = 'IOT-SIM-02',
    IsActive = true
  ),
  new Product2(
    Name = 'Remote SIM Provisioning Service',
    ProductCode = 'RSP-03',
    IsActive = true
  )
};
insert products;

List<Decimal> listPrices = new List<Decimal>{ 12, 4.5, 2500 };
List<PricebookEntry> entries = new List<PricebookEntry>();
for (Integer i = 0; i < products.size(); i++) {
  entries.add(
    new PricebookEntry(
      Pricebook2Id = standard.Id,
      Product2Id = products[i].Id,
      UnitPrice = listPrices[i],
      IsActive = true
    )
  );
}
insert entries;

Opportunity opp = new Opportunity(
  Name = 'Fleet Telematics Rollout 2027',
  StageName = 'Proposal/Price Quote',
  CloseDate = Date.today().addDays(45),
  Pricebook2Id = standard.Id
);
insert opp;

insert new List<OpportunityLineItem>{
  new OpportunityLineItem(
    OpportunityId = opp.Id,
    PricebookEntryId = entries[0].Id,
    Quantity = 5000,
    UnitPrice = 11
  ),
  new OpportunityLineItem(
    OpportunityId = opp.Id,
    PricebookEntryId = entries[1].Id,
    Quantity = 5000,
    UnitPrice = 4.5,
    Discount = 10
  ),
  new OpportunityLineItem(
    OpportunityId = opp.Id,
    PricebookEntryId = entries[2].Id,
    Quantity = 1,
    UnitPrice = 2500
  )
};
System.debug('Demo opportunity: ' + opp.Id);
