import matplotlib.pyplot as plt
import seaborn as sns

# CUSTOM PALETTES
MONOKAI_OCTAGON = ["#78dce8", "#a9dc76", "#ffd866", "#fc9867", "#ff6188", "#ab9df2"]

# FONT FAMILYS
SF_MONO = "SF Mono"
DEJAVU_SANS = "DejaVu Sans"

# SEABORN CONFIG
STYLE_CONFIG = {"context": "talk", "palette": MONOKAI_OCTAGON, "style": "darkgrid"}


def apply_style(style_config=STYLE_CONFIG, font_family=DEJAVU_SANS):
    """
    APPLY_STYLE - accepts of dict of seaborn style config values. Can be overwritten.
    See URL for Usage:
        https://seaborn.pydata.org/generated/seaborn.set_theme.html#seaborn.set_theme

    """
    print("Applying that fresh fresh... 😎")
    sns.set_theme(**style_config)
    plt.rcParams["font.family"] = font_family
    plt.rcParams["figure.figsize"] = [12, 6]
    plt.rcParams["grid.alpha"] = 0.3
    plt.rcParams["axes.spines.top"] = False
    plt.rcParams["axes.spines.right"] = False
    print("Freshness applied 🤌")
