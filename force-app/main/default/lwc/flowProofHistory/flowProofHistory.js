import { LightningElement, api, wire } from "lwc";
import { refreshApex } from "@salesforce/apex";
import getRecentInvestigations from "@salesforce/apex/FlowProofInvestigationController.getRecentInvestigations";
import { errorMessage, overallInfo } from "c/flowProofFormat";

const PAGE_SIZE = 50;

const COLUMNS = [
  {
    label: "Investigation",
    type: "button",
    typeAttributes: {
      label: { fieldName: "name" },
      name: "view",
      variant: "base",
      title: "View results"
    }
  },
  { label: "Flow", fieldName: "flowLabel", wrapText: true },
  { label: "Object", fieldName: "objectApiName" },
  { label: "Entry conditions", fieldName: "overallLabel" },
  { label: "Top finding", fieldName: "topFinding", wrapText: true },
  {
    label: "Findings",
    fieldName: "findingCount",
    type: "number",
    initialWidth: 100
  },
  {
    label: "When",
    fieldName: "createdDate",
    type: "date",
    typeAttributes: {
      year: "numeric",
      month: "short",
      day: "2-digit",
      hour: "2-digit",
      minute: "2-digit"
    }
  }
];

/**
 * Lists the user's recent investigations. Fires `viewinvestigation` with
 * { investigationId } when a row is opened.
 */
export default class FlowProofHistory extends LightningElement {
  columns = COLUMNS;
  rows = [];
  error;
  loaded = false;
  wiredResult;

  @wire(getRecentInvestigations, { limitSize: PAGE_SIZE })
  wiredInvestigations(result) {
    this.wiredResult = result;
    const { data, error } = result;
    if (data) {
      this.rows = data.map((row) => ({
        ...row,
        overallLabel: overallInfo(row.overallResult).label
      }));
      this.error = undefined;
      this.loaded = true;
    } else if (error) {
      this.rows = [];
      this.error = errorMessage(error);
      this.loaded = true;
    }
  }

  get loading() {
    return !this.loaded;
  }

  get hasRows() {
    return this.rows.length > 0;
  }

  get isEmpty() {
    return this.loaded && !this.error && this.rows.length === 0;
  }

  /**
   * Reloads the list from the server.
   * @returns {Promise} resolves when the list is refreshed
   */
  @api
  refresh() {
    return this.wiredResult ? refreshApex(this.wiredResult) : Promise.resolve();
  }

  handleRefresh() {
    this.refresh();
  }

  handleRowAction(event) {
    if (event.detail.action.name === "view") {
      this.dispatchEvent(
        new CustomEvent("viewinvestigation", {
          detail: { investigationId: event.detail.row.investigationId }
        })
      );
    }
  }
}
