# Localbrew
Simple package manager on top of homebrew. It manages dependencies locally.

## Instructions

1. Just put ```localbrew.rb``` and make it executable ```chmod +x localbrew.rb``` in your project folder
2. Create a ```localbrew.json``` file with the following format:
  ```
  {
    "require": {
      "jpeg": ["universal"]
    }
  }
  ```
3. Run ```./localbrew.rb``` to install dependencies
4. Add to your project the corresponding folders for headers ```.localbrew/include``` and libraries ```.localbrew/lib```
