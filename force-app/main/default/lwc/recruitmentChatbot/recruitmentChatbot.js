import { LightningElement, track } from 'lwc';
import processMessage from '@salesforce/apex/RecruitmentChatbotController.processMessage';

export default class RecruitmentChatbot extends LightningElement {
    @track isChatOpen = false;
    @track messages = [];
    @track currentMessage = '';
    @track isTyping = false;
    @track showQuickReplies = true;
    messageIdCounter = 0;

    connectedCallback() {
        // Welcome message
        this.addBotMessage(
            'Hello! 👋 I\'m your TalentForce Recruitment Assistant.\n\nI can help you with job recommendations, application status, interview schedule, and interview preparation.\n\nWhat can I help you with today?'
        );
    }

    toggleChat() {
        this.isChatOpen = !this.isChatOpen;
    }

    handleInput(event) {
        this.currentMessage = event.target.value;
    }

    handleKeyUp(event) {
        if (event.key === 'Enter' && this.currentMessage.trim()) {
            this.sendMessage();
        }
    }

    handleQuickReply(event) {
        this.currentMessage = event.target.dataset.message;
        this.sendMessage();
    }

    sendMessage() {
        const msg = this.currentMessage.trim();
        if (!msg) return;

        // Add user message
        this.addUserMessage(msg);
        this.currentMessage = '';
        this.showQuickReplies = false;
        this.isTyping = true;

        // Call Apex
        processMessage({ userMessage: msg, context: '' })
            .then(result => {
                this.isTyping = false;
                this.addBotMessage(result.response);
                this.scrollToBottom();
            })
            .catch(error => {
                this.isTyping = false;
                this.addBotMessage('Sorry, something went wrong. Please try again.');
                console.error(error);
            });
    }

    addUserMessage(text) {
        this.messages = [...this.messages, {
            id: this.messageIdCounter++,
            text: text,
            containerClass: 'msg-container user-container',
            bubbleClass: 'msg-bubble user-bubble',
            time: this.getCurrentTime()
        }];
        this.scrollToBottom();
    }

    addBotMessage(text) {
        this.messages = [...this.messages, {
            id: this.messageIdCounter++,
            text: text,
            containerClass: 'msg-container bot-container',
            bubbleClass: 'msg-bubble bot-bubble',
            time: this.getCurrentTime()
        }];
        this.scrollToBottom();
    }

    getCurrentTime() {
        const now = new Date();
        return now.getHours().toString().padStart(2, '0') + ':' +
               now.getMinutes().toString().padStart(2, '0');
    }

    scrollToBottom() {
        setTimeout(() => {
            const container = this.template.querySelector('.chat-messages');
            if (container) {
                container.scrollTop = container.scrollHeight;
            }
        }, 100);
    }
}