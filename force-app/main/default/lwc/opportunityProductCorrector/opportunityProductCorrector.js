import { LightningElement, api, wire } from "lwc";
import { refreshApex } from "@salesforce/apex";
import { ShowToastEvent } from "lightning/platformShowToastEvent";
import { notifyRecordUpdateAvailable } from "lightning/uiRecordApi";
import getLineItems from "@salesforce/apex/OpportunityProductController.getLineItems";
import saveCorrections from "@salesforce/apex/OpportunityProductController.saveCorrections";

// Discount is shown as a plain number because Apex returns 15 for 15%,
// while the datatable "percent" type expects 0.15.
const COLUMNS = [
  { label: "Product", fieldName: "productName" },
  { label: "Code", fieldName: "ProductCode" },
  { label: "Quantity", fieldName: "Quantity", type: "number", editable: true },
  {
    label: "Sales Price",
    fieldName: "UnitPrice",
    type: "currency",
    editable: true
  },
  { label: "List Price", fieldName: "ListPrice", type: "currency" },
  {
    label: "Discount (%)",
    fieldName: "Discount",
    type: "number",
    editable: true,
    typeAttributes: { maximumFractionDigits: 2 }
  },
  { label: "Total", fieldName: "TotalPrice", type: "currency" }
];

const NUMBER_FIELDS = ["Quantity", "UnitPrice", "Discount"];

export function reduceError(error) {
  return error?.body?.message || error?.message || "Unknown error";
}

// Datatable drafts hold strings ("12"); Apex expects numbers. An emptied cell becomes null.
export function toApexDrafts(draftValues) {
  return draftValues.map((draft) => {
    const record = { Id: draft.Id };
    NUMBER_FIELDS.forEach((field) => {
      if (field in draft) {
        record[field] = draft[field] === "" ? null : Number(draft[field]);
      }
    });
    return record;
  });
}

export default class OpportunityProductCorrector extends LightningElement {
  @api recordId;

  columns = COLUMNS;
  rows = [];
  draftValues = [];
  reason = "";
  error;
  isSaving = false;
  wiredLineItems;

  @wire(getLineItems, { opportunityId: "$recordId" })
  handleLineItems(result) {
    this.wiredLineItems = result;
    if (result.data) {
      this.rows = result.data.map((item) => ({
        ...item,
        productName: item.Product2?.Name
      }));
      this.error = undefined;
    } else if (result.error) {
      this.rows = [];
      this.error = reduceError(result.error);
    }
  }

  get hasRows() {
    return this.rows.length > 0;
  }

  handleReasonChange(event) {
    this.reason = event.target.value;
  }

  handleCancel() {
    this.draftValues = [];
  }

  async handleSave(event) {
    const drafts = event.detail.draftValues;
    if (!this.reason || !this.reason.trim()) {
      this.toast(
        "Reason required",
        "Enter a reason before saving the correction.",
        "warning"
      );
      return;
    }

    this.isSaving = true;
    try {
      const updated = await saveCorrections({
        drafts: toApexDrafts(drafts),
        reason: this.reason
      });
      this.toast(
        "Corrections saved",
        `${updated} product line(s) updated.`,
        "success"
      );
      this.draftValues = [];
      this.reason = "";
      await refreshApex(this.wiredLineItems);
      // Lets the Opportunity Amount and related lists on the page refresh too.
      await notifyRecordUpdateAvailable([{ recordId: this.recordId }]);
    } catch (error) {
      this.toast("Could not save corrections", reduceError(error), "error");
    } finally {
      this.isSaving = false;
    }
  }

  toast(title, message, variant) {
    this.dispatchEvent(new ShowToastEvent({ title, message, variant }));
  }
}
