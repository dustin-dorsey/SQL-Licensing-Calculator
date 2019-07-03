# SQL-Licensing-Calculator

The SQL licensing Calculator is a free easy-to-use and independent script that you can start using to help you make better decisions with your licensing, compare different models and avoid costly mistakes. By passing through a few values, you can instantly evaluate what your costs are and review any potential gotcha’s or compliance issues you may not have thought of. There are two results that are returned. The first one is a recap of how you are licensing along with the cost. The second result is any considerations regarding the build or licensing that you need to be mindful of separated out based on criticality (Critical, Warning, Informational) with links for more information.

You can view more information about this tool by visiting - https://dustindorsey.com/sql-licensing-calculator/

Disclaimer: By using this tool you agree to do so at your own risk and understand this is not something created by or representative of Microsoft. I highly encourage your to read through the SQL licensing guides and continue working with your licensing providers. Based on years of experience, working with Microsoft and licensed re-sellers on licensing and careful review of the licensing guides I believe the information contained in this is correct, however, its possible something could be wrong. My intention is not to deceive anyone with any misinformation and will gladly receive feedback and update this as information is verified. This tool is not a replacement for determining exact costs and may not cover everything specific to your agreement, rather it is a tool that can be used to help in your decision making.

Click here to download a copy of the SQL 2017 licensing guide or click here to download a copy of the SQL 2017 licensing datasheet (condensed version)

Requirements: The script must be ran on a SQL 2008 or later version. Once created the only permission that is needed is EXECUTE rights on the stored proc.

Existing Limitations of this tool:
1. Licensing for Parallel Data Warehouse (PDW) is not supported at this time
2. If you do not enter a value for your costs, then MSRP\Estimated costs are used which is currently represented in US dollars. For other currencies, you will need to enter numbers for the costs to get an accurate number (avoid default values)

When you run the script, it will provide a list of considerations based on what you entered. While there is a short snippet that supplies information there is more that can be discussed on that topic. There are links back to pages on this site that provide deeper information about the consideration. I am linking them here as well.
