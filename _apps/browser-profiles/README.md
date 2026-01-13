# browser-profiles

A simple utility to launch Chrome with specific user profiles.

## Usage

```powershell
# List all available profiles
browser-profiles list

# Open a specific profile (partial match supported)
browser-profiles open Work
browser-profiles open "Personal"

# Quick access - just use the profile name directly
browser-profiles Work

# Show configuration
browser-profiles config
```

## Features

- Auto-discovers Chrome profiles from the local user data directory
- Partial name matching for convenience
- Shows profile email/account when available

## Future Ideas

- Support for Edge, Firefox, Brave
- Custom profile aliases
- Open with specific URLs
- Profile groups (open multiple profiles at once)
