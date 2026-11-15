{{flutter_js}}
{{flutter_build_config}}

// Runs the app inside the phone frame of index.html instead of the whole page.
_flutter.loader.load({
  onEntrypointLoaded: async (engineInitializer) => {
    const appRunner = await engineInitializer.initializeEngine({
      hostElement: document.querySelector("#app"),
    });
    await appRunner.runApp();
  },
});
