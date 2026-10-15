ALTER TABLE `settings` ADD `onboarding_message_id` integer REFERENCES messages(id) ON DELETE set null;--> statement-breakpoint
ALTER TABLE `settings` ADD `onboarding_role_id` integer REFERENCES roles(id) ON DELETE set null;
