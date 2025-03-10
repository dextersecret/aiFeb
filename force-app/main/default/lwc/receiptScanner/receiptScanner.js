import { LightningElement, track } from 'lwc';
import processReceipt from '@salesforce/apex/ReceiptProcessor.processReceipt';
import { ShowToastEvent } from 'lightning/platformShowToastEvent';

export default class ReceiptScanner extends LightningElement {
    @track imageUrl;
    @track imageUploaded = false;
    @track lineItems = [];
    @track contentDocumentId;

    // Computed property for subtotal
    get subtotal() {
        return this.lineItems.reduce((sum, item) => sum + (parseFloat(item.price) || 0), 0);
    }

    // Handle file upload and generate preview
    handleUploadFinished(event) {
        const uploadedFile = event.detail.files[0];
        this.contentDocumentId = uploadedFile.documentId;
        this.imageUrl = `/sfc/servlet.shepherd/document/download/${this.contentDocumentId}`;
        this.imageUploaded = true;
    }

    // Process receipt with xAI Grok Vision
    handleProcessReceipt() {
        processReceipt({ contentDocumentId: this.contentDocumentId })
            .then(result => {
                const parsedResult = JSON.parse(result);
                let parsedLineItems = parsedResult.lineItems.map((item, index) => ({
                    id: index,
                    name: item.name,
                    price: item.price
                }));
                this.lineItems.push(...parsedLineItems);
            })
            .catch(error => {
                this.showToast('Error', error.body.message, 'error');
            });
    }

    // Handle name change
    handleNameChange(event) {
        const index = event.target.dataset.index;
        this.lineItems[index].name = event.target.value;
        this.lineItems = [...this.lineItems]; // Trigger reactivity
    }

    // Handle price change
    handlePriceChange(event) {
        const index = event.target.dataset.index;
        this.lineItems[index].price = parseFloat(event.target.value) || 0;
        this.lineItems = [...this.lineItems]; // Trigger reactivity
    }

    // Remove line item
    handleRemoveItem(event) {
        const index = event.target.dataset.index;
        this.lineItems.splice(index, 1);
        this.lineItems = this.lineItems.map((item, i) => ({ ...item, id: i }));
    }

    // Add new empty item
    handleAddItem() {
        this.lineItems.push({
            id: this.lineItems.length,
            name: '',
            price: 0
        });
        this.lineItems = [...this.lineItems];
    }

    // Show toast notification
    showToast(title, message, variant) {
        const evt = new ShowToastEvent({ title, message, variant });
        this.dispatchEvent(evt);
    }
}