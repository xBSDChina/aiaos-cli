# AIAOS-CLI Skills

Skills are reusable command modules that extend AIAOS-CLI functionality.

## Skill Structure

Each skill is a directory containing:
- `skill.yaml` - Skill metadata
- `commands/` - Command implementations
- `hooks/` - Event hooks

## Available Skills

### Git Skills

- `git-commit` - Commit changes to git
- `git-push` - Push changes to remote
- `git-pull` - Pull changes from remote
- `git-status` - Show git status

### Docker Skills

- `docker-build` - Build a Docker image
- `docker-run` - Run a Docker container
- `docker-stop` - Stop a Docker container

### System Skills

- `system-info` - Show system information
- `disk-usage` - Show disk usage
- `memory-usage` - Show memory usage

### LLM Skills

- `llm-chat` - Chat with an LLM
- `llm-analyze` - Analyze text with LLM
- `llm-translate` - Translate text with LLM

## Creating a Skill

1. Create a directory under `~/aiaos/aiaos-cli/skills/`
2. Create `skill.yaml`:
   ```yaml
   name: my-skill
   version: 1.0.0
   description: My custom skill
   commands:
     - name: hello
       description: Say hello
       file: commands/hello.el
   ```
3. Create command implementation in `commands/hello.el`:
   ```elisp
   (defun my-skill-hello ()
     "Say hello."
     (message "Hello, World!"))
   ```
4. Load the skill:
   ```elisp
   (aiaos-cli-skill-load "my-skill")
   ```

## Skill Commands

### aiaos-cli-skill-load

```elisp
(aiaos-cli-skill-load SKILL-NAME)
```

Load a skill by name.

### aiaos-cli-skill-list

```elisp
(aiaos-cli-skill-list)
```

List all loaded skills.

### aiaos-cli-skill-execute

```elisp
(aiaos-cli-skill-execute SKILL-NAME COMMAND-NAME &rest ARGS)
```

Execute a skill command.