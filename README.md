
# TalentForce Recruit — Salesforce Recruitment Platform

A Salesforce-native AI-powered recruitment management platform built to handle the full hiring lifecycle, from job position creation to contract signing.

## Overview

TalentForce Recruit is built entirely within a Salesforce org using native platform capabilities. It manages the complete candidate lifecycle: job position creation, candidate application and qualification, interview stages, offer approval, contract generation, and final hiring.

## Built With

- **Apex** — Backend logic, services, triggers, and scheduled jobs
- **Lightning Web Components (LWC)** — Custom UI components
- **Salesforce Flows** — Stage transitions, automations, and field updates
- **Agentforce** — AI agent available to candidates, recruiters, interviewers, and hiring managers
- **Experience Cloud** — Candidate-facing portal for job discovery and application
- **Approval Process** — Native offer approval workflow for hiring managers

## Key Features

- Job position creation with requirements (skills, education, experience)
- Candidate intake form via Experience Cloud with automatic Lead creation
- Automatic qualification scoring based on candidate profile
- Sequential interview stages (HR, Technical, Manager) with conditional progression
- Final applicant score calculation (initial score + interview scores)
- Offer approval process for hiring managers
- Automated contract generation and sending with 48-hour signing deadline
- Contract expiry and automatic candidate reranking
- AI agent serving candidates, recruiters, interviewers, and hiring managers

## Project Structure


force-app/
  main/
    default/
      classes/        # Apex classes and controllers
      triggers/       # Apex triggers
      flows/          # Salesforce Flows
      lwc/            # Lightning Web Components
      objects/        # Custom objects and fields
      permissionsets/ # Permission sets per role
      profiles/       # User profiles
      approvalProcesses/ # Offer approval process


## Roles

| Role | Description |
|------|-------------|
| Recruiter | Manages job positions, candidates, and contracts |
| Hiring Manager | Reviews and approves/rejects offers |
| Interviewer | Conducts interviews and records scores |
| Candidate | Applies via portal and tracks application status |

