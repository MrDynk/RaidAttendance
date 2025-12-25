# Copilot Instructions for Helper Addon

This file provides guidance for the language model (LLM) to reference when answering questions about the Helper addon project. It includes details about the addon's functionality, structure, and usage.

## Purpose
The Helper addon is designed for Turtle WoW to assist players in managing raid attendance and tracking changes in party or raid members. The LLM should use the information in this file to provide accurate and context-aware responses.

## Key Details
- **Slash Commands**:
  - `/start`: Begins tracking raid attendance. Logs members joining or leaving the raid.


- **File Structure**:
  - `Helper.lua`: Contains the main logic for the addon.
  - `Helper.toc`: Metadata file listing the addon's components.
  - `wow-api-type-definitions-main`: Contains API definitions for Turtle WoW, including available events and functions.

## LLM Reference Notes
- When answering questions about the Helper addon, reference the `wow-api-type-definitions-main` folder for API details.
- Provide examples of how the `/start` command and event handling work.
- Emphasize the addon's purpose: tracking raid attendance and logging changes.
- Use the file structure to guide users to relevant parts of the project.

---

For further clarification, refer to the Turtle WoW API documentation or contact the addon developer.