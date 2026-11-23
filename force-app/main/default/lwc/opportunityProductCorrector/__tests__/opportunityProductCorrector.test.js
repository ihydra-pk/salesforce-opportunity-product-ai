import { createElement } from "lwc";
import OpportunityProductCorrector, {
  toApexDrafts
} from "c/opportunityProductCorrector";
import getLineItems from "@salesforce/apex/OpportunityProductController.getLineItems";
import saveCorrections from "@salesforce/apex/OpportunityProductController.saveCorrections";
import reviewProducts from "@salesforce/apex/ProductHealthAIController.reviewProducts";
import { notifyRecordUpdateAvailable } from "lightning/uiRecordApi";

jest.mock(
  "@salesforce/apex/OpportunityProductController.getLineItems",
  () => {
    const { createApexTestWireAdapter } = require("@salesforce/sfdx-lwc-jest");
    return { default: createApexTestWireAdapter(jest.fn()) };
  },
  { virtual: true }
);
jest.mock(
  "@salesforce/apex/OpportunityProductController.saveCorrections",
  () => ({ default: jest.fn() }),
  {
    virtual: true
  }
);
jest.mock(
  "@salesforce/apex/ProductHealthAIController.reviewProducts",
  () => ({ default: jest.fn() }),
  { virtual: true }
);
jest.mock(
  "lightning/uiRecordApi",
  () => ({ notifyRecordUpdateAvailable: jest.fn(() => Promise.resolve()) }),
  {
    virtual: true
  }
);

const LINE_ITEMS = [
  {
    Id: "00k000000000001AAA",
    Product2: { Name: "eSIM Plan" },
    ProductCode: "ESIM-01",
    Quantity: 10,
    UnitPrice: 100
  },
  {
    Id: "00k000000000002AAA",
    Product2: { Name: "IoT SIM" },
    ProductCode: "IOT-01",
    Quantity: 5,
    UnitPrice: 20
  }
];

const TOAST_EVENT = "lightning__showtoast";
// Lets pending promises (wire emits, Apex calls) settle before asserting.
const flushPromises = () => new Promise((resolve) => process.nextTick(resolve));

function render() {
  const element = createElement("c-opportunity-product-corrector", {
    is: OpportunityProductCorrector
  });
  element.recordId = "006000000000001AAA";
  document.body.appendChild(element);
  return element;
}

function setReason(element, value) {
  const input = element.shadowRoot.querySelector('[data-id="reason"]');
  input.value = value;
  input.dispatchEvent(new CustomEvent("change"));
}

function saveDrafts(element, draftValues) {
  const table = element.shadowRoot.querySelector("lightning-datatable");
  table.dispatchEvent(new CustomEvent("save", { detail: { draftValues } }));
}

describe("c-opportunity-product-corrector", () => {
  afterEach(() => {
    while (document.body.firstChild) {
      document.body.removeChild(document.body.firstChild);
    }
    jest.clearAllMocks();
  });

  it("shows the opportunity products in the table", async () => {
    const element = render();
    getLineItems.emit(LINE_ITEMS);
    await flushPromises();

    const table = element.shadowRoot.querySelector("lightning-datatable");
    expect(table.data).toHaveLength(2);
    expect(table.data[0].productName).toBe("eSIM Plan");
  });

  it("shows a message when the opportunity has no products", async () => {
    const element = render();
    getLineItems.emit([]);
    await flushPromises();

    expect(
      element.shadowRoot.querySelector('[data-id="empty"]')
    ).not.toBeNull();
    expect(element.shadowRoot.querySelector("lightning-datatable")).toBeNull();
  });

  it("shows the error when products cannot be loaded", async () => {
    const element = render();
    getLineItems.error({ message: "Insufficient access" });
    await flushPromises();

    expect(
      element.shadowRoot.querySelector('[data-id="error"]').textContent
    ).toBe("Insufficient access");
  });

  it("does not save without a reason", async () => {
    const element = render();
    getLineItems.emit(LINE_ITEMS);
    await flushPromises();
    const toastHandler = jest.fn();
    element.addEventListener(TOAST_EVENT, toastHandler);

    saveDrafts(element, [{ Id: LINE_ITEMS[0].Id, Quantity: "12" }]);
    await flushPromises();

    expect(saveCorrections).not.toHaveBeenCalled();
    expect(toastHandler.mock.calls[0][0].detail.variant).toBe("warning");
  });

  it("saves drafts as numbers with the reason", async () => {
    saveCorrections.mockResolvedValue(1);
    const element = render();
    getLineItems.emit(LINE_ITEMS);
    await flushPromises();
    const toastHandler = jest.fn();
    element.addEventListener(TOAST_EVENT, toastHandler);

    setReason(element, "Customer ordered 2 more units");
    saveDrafts(element, [{ Id: LINE_ITEMS[0].Id, Quantity: "12" }]);
    await flushPromises();

    expect(saveCorrections).toHaveBeenCalledWith({
      drafts: [{ Id: LINE_ITEMS[0].Id, Quantity: 12 }],
      reason: "Customer ordered 2 more units"
    });
    expect(toastHandler.mock.calls[0][0].detail.variant).toBe("success");
    // The opportunity and the changed line are refreshed on the page.
    expect(notifyRecordUpdateAvailable).toHaveBeenCalledWith([
      { recordId: "006000000000001AAA" },
      { recordId: LINE_ITEMS[0].Id }
    ]);
  });

  it("shows the server error when saving fails", async () => {
    saveCorrections.mockRejectedValue({
      body: { message: "Discount cannot exceed 50%." }
    });
    const element = render();
    getLineItems.emit(LINE_ITEMS);
    await flushPromises();
    const toastHandler = jest.fn();
    element.addEventListener(TOAST_EVENT, toastHandler);

    setReason(element, "Big discount");
    saveDrafts(element, [{ Id: LINE_ITEMS[0].Id, Discount: "60" }]);
    await flushPromises();

    const toast = toastHandler.mock.calls[0][0].detail;
    expect(toast.variant).toBe("error");
    expect(toast.message).toBe("Discount cannot exceed 50%.");
  });

  it("shows the AI review for the opportunity", async () => {
    reviewProducts.mockResolvedValue("- eSIM Plan: price is 83% above list.");
    const element = render();
    getLineItems.emit(LINE_ITEMS);
    await flushPromises();

    element.shadowRoot
      .querySelector('[data-id="ai-review-button"]')
      .dispatchEvent(new CustomEvent("click"));
    await flushPromises();

    expect(reviewProducts).toHaveBeenCalledWith({
      opportunityId: "006000000000001AAA"
    });
    expect(
      element.shadowRoot.querySelector('[data-id="ai-review"]').textContent
    ).toContain("83% above list");
  });

  it("shows an error toast when the AI review fails", async () => {
    reviewProducts.mockRejectedValue({
      body: { message: "AI review failed: Model unavailable" }
    });
    const element = render();
    getLineItems.emit(LINE_ITEMS);
    await flushPromises();
    const toastHandler = jest.fn();
    element.addEventListener(TOAST_EVENT, toastHandler);

    element.shadowRoot
      .querySelector('[data-id="ai-review-button"]')
      .dispatchEvent(new CustomEvent("click"));
    await flushPromises();

    expect(toastHandler.mock.calls[0][0].detail.variant).toBe("error");
    expect(
      element.shadowRoot.querySelector('[data-id="ai-review"]')
    ).toBeNull();
  });
});

describe("toApexDrafts", () => {
  it("converts edited cells to numbers and empty cells to null", () => {
    expect(
      toApexDrafts([{ Id: "a", Quantity: "3", UnitPrice: "9.5", Discount: "" }])
    ).toEqual([{ Id: "a", Quantity: 3, UnitPrice: 9.5, Discount: null }]);
  });
});
