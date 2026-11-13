from typing import Annotated

from pydantic import BaseModel, StringConstraints

#: Yahoo symbols such as AAPL, BRK-B, THYAO.IS or ARB11841-USD. Lower case is
#: allowed because the pattern is checked before the symbol is upper-cased.
SYMBOL_PATTERN = r"^[A-Za-z0-9^][A-Za-z0-9.\-=&^]{0,19}$"


class AddCatalogAssetRequest(BaseModel):
    symbol: Annotated[str, StringConstraints(strip_whitespace=True, to_upper=True, pattern=SYMBOL_PATTERN)]
