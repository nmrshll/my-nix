let
  aiSkills = (import ./ai-skills.nix).flake.flakeModules.ai-skills;
  bundle = skills: {
    imports = [ aiSkills ];
    aiSkills.skills = builtins.listToAttrs (map (name: {
      inherit name;
      value = ../skills + "/${name}";
    }) skills);
  };
  flakeModules = {
    frontend = bundle [
      "accessibility-states"
      "app-shell-navigation"
      "artifact-composition" # Required by navigation and chart rendering.
      "chart-rendering"
      "cjk-typography"
      "craft-polish"
      "data-viz-recharts"
      "design-reference-to-html"
      "design-system-baton"
      "empty-states"
      "form-layout"
      "frontend-design-anti-slop"
      "loading-skeleton"
      "mobile-mock"
      "responsive-layout"
      "static-website-ui"
      "surface-elevation"
      "ui-design-system"
    ];
    artifact-design = bundle [ "artifact-composition" "pitch-deck" ];
    git-xet = bundle [ "huggingface-git-xet" ];
    gpui = bundle [ "gpui-async" ];
  };
in
{
  flake.flakeModules = flakeModules;
  imports = builtins.attrValues flakeModules;
}
