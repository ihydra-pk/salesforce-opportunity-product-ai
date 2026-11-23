/**
 * Grounding for the Opportunity_Product_Health_Review prompt template.
 * Checks each Opportunity Product against fixed pricing rules and returns
 * the facts as text. The AI only explains and prioritises these facts;
 * it doesn't calculate anything itself, so it can't invent numbers.
 */
public with sharing class ProductHealthGrounding {
  @TestVisible
  private static final Decimal HIGH_DISCOUNT_PERCENT = 20;
  @TestVisible
  private static final Decimal MAX_BELOW_LIST_PERCENT = 30;
  @TestVisible
  private static final Decimal LARGE_VOLUME = 1000;

  public class Request {
    @InvocableVariable(required=true)
    public Opportunity myOpportunity;
  }

  public class Response {
    @InvocableVariable
    public String Prompt;
  }

  @InvocableMethod(
    label='Opportunity Product Health Facts'
    description='Returns the products of an Opportunity with pricing flags, for the product health prompt template.'
  )
  public static List<Response> getFacts(List<Request> requests) {
    List<Response> responses = new List<Response>();
    for (Request request : requests) {
      Response response = new Response();
      response.Prompt = describe(request.myOpportunity.Id);
      responses.add(response);
    }
    return responses;
  }

  public static String describe(Id opportunityId) {
    Opportunity opp = [
      SELECT
        Name,
        StageName,
        CloseDate,
        Amount,
        (
          SELECT
            Product2.Name,
            ProductCode,
            Quantity,
            UnitPrice,
            ListPrice,
            Discount,
            TotalPrice
          FROM OpportunityLineItems
          ORDER BY Product2.Name
        )
      FROM Opportunity
      WHERE Id = :opportunityId
      WITH USER_MODE
    ];

    List<String> lines = new List<String>{
      'Opportunity: ' + opp.Name,
      'Stage: ' +
      opp.StageName +
      ', close date: ' +
      opp.CloseDate +
      ', amount: ' +
      opp.Amount,
      'Products:'
    };
    if (opp.OpportunityLineItems.isEmpty()) {
      lines.add('- none');
    }
    for (OpportunityLineItem item : opp.OpportunityLineItems) {
      List<String> flags = flagsFor(
        item.Quantity,
        item.UnitPrice,
        item.ListPrice,
        item.Discount
      );
      lines.add(
        '- ' +
          item.Product2.Name +
          ' (' +
          item.ProductCode +
          '): quantity ' +
          item.Quantity +
          ', sales price ' +
          item.UnitPrice +
          ', list price ' +
          item.ListPrice +
          ', discount ' +
          (item.Discount == null ? 0 : item.Discount) +
          '%, total ' +
          item.TotalPrice +
          '. Flags: ' +
          (flags.isEmpty() ? 'none' : String.join(flags, '; '))
      );
    }
    return String.join(lines, '\n');
  }

  @TestVisible
  private static List<String> flagsFor(
    Decimal quantity,
    Decimal unitPrice,
    Decimal listPrice,
    Decimal discountPercent
  ) {
    List<String> flags = new List<String>();
    Decimal discount = discountPercent == null ? 0 : discountPercent;

    if (discount > HIGH_DISCOUNT_PERCENT) {
      flags.add(
        'discount ' +
          discount +
          '% is above the ' +
          HIGH_DISCOUNT_PERCENT +
          '% review threshold'
      );
    }
    if (listPrice != null && listPrice > 0) {
      Decimal differencePercent = ((unitPrice - listPrice) /
        listPrice *
        100)
        .setScale(0);
      if (differencePercent > 0) {
        flags.add('sales price is ' + differencePercent + '% above list price');
      } else if (-differencePercent > MAX_BELOW_LIST_PERCENT) {
        flags.add(
          'sales price is ' + (-differencePercent) + '% below list price'
        );
      }
      if (quantity >= LARGE_VOLUME && unitPrice == listPrice && discount == 0) {
        flags.add('large volume at full list price, check volume pricing');
      }
    }
    return flags;
  }
}
