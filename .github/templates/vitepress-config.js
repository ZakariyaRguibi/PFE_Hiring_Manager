export default {
  title: "PFE Hiring Manager — Documentation",
  description: "Apex documentation for the PFE Hiring Manager Salesforce project",
  base: "/PFE_Hiring_Manager/",
  themeConfig: {
    nav: [
      { text: "Home", link: "/" },
      { text: "API Reference", link: "/markdown/" },
      { text: "Changelog", link: "/changelog/changelog" },
      {
        text: "Code Analyzer",
        link: "https://zakariyarguibi.github.io/PFE_Hiring_Manager/report.html"
      }
    ],
    sidebar: {
      "/markdown/": [
        {
          text: "API Documentation",
          items: [{ text: "Index", link: "/markdown/" }]
        }
      ],
      "/changelog/": [
        {
          text: "Changelog",
          items: [{ text: "Changelog", link: "/changelog/changelog" }]
        }
      ]
    },
    socialLinks: [
      {
        icon: "github",
        link: "https://github.com/ZakariyaRguibi/PFE_Hiring_Manager"
      }
    ],
    footer: {
      message: "Generated with ApexDocs and VitePress",
      copyright: "Copyright © PFE Hiring Manager Project"
    }
  }
};
