import { LightningElement } from 'lwc';
import registerCandidate from '@salesforce/apex/CandidatePortalRegistrationController.registerCandidate';

export default class CandidateRegistrationForm extends LightningElement {
    formData = {
        firstName: '',
        lastName: '',
        email: '',
        phone: '',
        educationLevel: '',
        yearsOfExperience: null,
        password: '',
        confirmPassword: ''
    };

    isLoading = false;
    errorMessage;
    successMessage;

    handleChange(event) {
        const field = event.target.dataset.field;
        this.formData = {
            ...this.formData,
            [field]: event.target.value
        };
    }

    async handleRegister() {
        this.errorMessage = undefined;
        this.successMessage = undefined;

        if (!this.isFormValid()) {
            return;
        }

        this.isLoading = true;

        try {
            const result = await registerCandidate({
                firstName: this.formData.firstName,
                lastName: this.formData.lastName,
                email: this.formData.email,
                phone: this.formData.phone,
                educationLevel: this.formData.educationLevel,
                yearsOfExperience: Number(this.formData.yearsOfExperience),
                password: this.formData.password,
                confirmPassword: this.formData.confirmPassword
            });

            if (result && result.success) {
                this.successMessage = result.message;
                this.errorMessage = undefined;
            } else {
                this.errorMessage = result?.message || 'Registration failed.';
            }
        } catch (error) {
            this.errorMessage = this.extractErrorMessage(error);
        } finally {
            this.isLoading = false;
        }
    }

    isFormValid() {
        const requiredFields = [
            'firstName',
            'lastName',
            'email',
            'phone',
            'educationLevel',
            'yearsOfExperience',
            'password',
            'confirmPassword'
        ];

        for (const field of requiredFields) {
            if (!this.formData[field] && this.formData[field] !== 0) {
                this.errorMessage = 'Please fill in all required fields.';
                return false;
            }
        }

        if (this.formData.password !== this.formData.confirmPassword) {
            this.errorMessage = 'Password and confirmation do not match.';
            return false;
        }

        if (this.formData.password.length < 8) {
            this.errorMessage = 'Password must contain at least 8 characters.';
            return false;
        }

        return true;
    }

    extractErrorMessage(error) {
        if (error?.body?.message) {
            return error.body.message;
        }

        if (Array.isArray(error?.body)) {
            return error.body.map((e) => e.message).join(', ');
        }

        return 'An unexpected error occurred during registration.';
    }

    goToLogin() {
        window.location.href = '/talentforce/login';
    }
}