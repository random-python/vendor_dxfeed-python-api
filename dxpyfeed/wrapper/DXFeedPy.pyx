# distutils: language = c++
from libcpp.deque cimport deque as cppdq

from dxpyfeed.wrapper.utils.helpers cimport *
from dxpyfeed.wrapper.utils.helpers import *
cimport dxpyfeed.wrapper.pxd_include.DXFeed as clib
cimport dxpyfeed.wrapper.pxd_include.DXErrorCodes as dxec
cimport dxpyfeed.wrapper.listeners.listener as lis
from collections import deque
from datetime import datetime
import pandas as pd
from typing import Optional, Union

# for importing variables
import dxpyfeed.wrapper.listeners.listener as lis
from dxpyfeed.wrapper.pxd_include.EventData cimport *

# for debugging
# from libc.stdint cimport uintptr_t


cpdef int process_last_error(verbose: bool = True):
    """
    Function retrieves last error

    Parameters
    ----------
    verbose: bool
        If True error description is printed
        
    Returns
    -------
    error_code: int
        Error code is returned
    """
    cdef int error_code = dxec.dx_ec_success
    cdef dxf_const_string_t error_descr = NULL
    cdef int res

    res = clib.dxf_get_last_error(&error_code, &error_descr)

    if res == clib.DXF_SUCCESS:
        if error_code == dxec.dx_ec_success and verbose:
            print("no error information is stored")

        if verbose:
            print("Error occurred and successfully retrieved:\n",
                  f"error code = {error_code}, description = {unicode_from_dxf_const_string_t(error_descr)}")

    return error_code

cdef class ConnectionClass:
    """
    Data structure that contains connection
    """
    cdef clib.dxf_connection_t connection
    # sub_ptr_list contains pointers to all subscriptions related to current connection
    cdef cppdq[clib.dxf_subscription_t *] sub_ptr_list
    # each subscription has its own index in a list
    cdef int subs_order

    def __init__(self):
        self.subs_order = 0

    def __dealloc__(self):
        dxf_close_connection(self)

    cpdef SubscriptionClass make_new_subscription(self, data_len):
        cdef SubscriptionClass out = SubscriptionClass(data_len)
        out.connection = self.connection
        self.sub_ptr_list.push_back(&out.subscription)  # append pointer to new subscription
        out.subscription_order = self.subs_order  # assign each subscription an index
        self.subs_order += 1
        out.con_sub_list_ptr = &self.sub_ptr_list  # reverse pointer to pointers list
        return out

cdef class SubscriptionClass:
    """
    Data structure that contains subscription and related fields

    Parameters
    ----------
    data_len: int
        Sets maximum amount of events, that are kept in Subscription class
    """
    cdef clib.dxf_connection_t connection
    cdef clib.dxf_subscription_t subscription
    cdef int subscription_order  # index in list of subscription pointers
    cdef cppdq[clib.dxf_subscription_t *] *con_sub_list_ptr  # pointer to list of subscription pointers
    cdef dxf_event_listener_t listener
    cdef object event_type_str
    cdef dict data
    cdef void *u_data

    def __init__(self, data_len):
        self.subscription = NULL
        self.data = {'columns': []}
        if data_len > 0:
            self.data.update({'data': deque(maxlen=data_len)})
        else:
            self.data.update({'data': []})
        self.u_data = <void *> self.data
        self.listener = NULL

    def __dealloc__(self):
        if self.subscription:  # if connection is not closed
            clib.dxf_close_subscription(self.subscription)
            # self.subscription = NULL
            # mark subscription as closed in list of pointers to subscriptions
            self.con_sub_list_ptr[0][self.subscription_order] = NULL

    @property
    def data(self):
        return self.data

    @data.setter
    def data(self, new_val: dict):
        self.data = new_val

    def to_dataframe(self):
        """
        Method converts dict of data to the Pandas DataFrame

        Returns
        -------
        df: pandas DataFrame
        """
        arr_len = len(self.data['data'])
        df = pd.DataFrame(list(self.data['data'])[:arr_len], columns=self.data['columns'])
        time_columns = df.columns[df.columns.str.contains('Time')]
        for column in time_columns:
            df.loc[:, column] = df.loc[:, column].astype('<M8[ms]')
        return df

def dxf_create_connection(address: Union[str, unicode, bytes] = 'demo.dxfeed.com:7300'):
    """
    Function creates connection to dxfeed given url address

    Parameters
    ----------
    address: str
        dxfeed url address

    Returns
    -------
    cc: ConnectionClass
        Cython ConnectionClass with information about connection
    """
    cc = ConnectionClass()
    address = address.encode('utf-8')
    clib.dxf_create_connection(address, NULL, NULL, NULL, NULL, NULL, &cc.connection)
    error_code = process_last_error(verbose=False)
    if error_code:
        raise RuntimeError(f"In underlying C-API library error {error_code} occurred!")
    return cc

def dxf_create_subscription(ConnectionClass cc, event_type: str, candle_time: Optional[str] = None, data_len: int = 0):
    """
    Function creates subscription and writes all relevant information to SubscriptionClass
    Parameters
    ----------
    cc: ConnectionClass
        Variable with connection information
    event_type: str
        Event types: 'Trade', 'Quote', 'Summary', 'Profile', 'Order', 'TimeAndSale', 'Candle', 'TradeETH', 'SpreadOrder',
                    'Greeks', 'THEO_PRICE', 'Underlying', 'Series', 'Configuration' or ''
    candle_time: str
        String of %Y-%m-%d %H:%M:%S datetime format for retrieving candles. By default set to now
    data_len: int
        Sets maximum amount of events, that are kept in Subscription class

    Returns
    -------
    sc: SubscriptionClass
        Cython SubscriptionClass with information about subscription
    """
    if not cc.connection:
        raise ValueError('Connection is not valid')

    sc = cc.make_new_subscription(data_len=data_len)
    sc.event_type_str = event_type
    et_type_int = event_type_convert(event_type)

    try:
        candle_time = datetime.strptime(candle_time, '%Y-%m-%d %H:%M:%S') if candle_time else datetime.utcnow()
        timestamp = int((candle_time - datetime(1970, 1, 1)).total_seconds()) * 1000 - 5000
    except ValueError:
        raise Exception("Inapropriate date format, should be %Y-%m-%d %H:%M:%S")

    if event_type == 'Candle':
        clib.dxf_create_subscription_timed(sc.connection, et_type_int, timestamp, &sc.subscription)
    else:
        clib.dxf_create_subscription(sc.connection, et_type_int, &sc.subscription)

    error_code = process_last_error(verbose=False)
    if error_code:
        raise RuntimeError(f"In underlying C-API library error {error_code} occurred!")
    return sc

def dxf_add_symbols(SubscriptionClass sc, symbols: list):
    """
    Adds symbols to subscription
    Parameters
    ----------
    sc: SubscriptionClass
        SubscriptionClass with information about subscription
    symbols: list
        List of symbols to add
    """
    if not sc.subscription:
        raise ValueError('Subscription is not valid')
    for idx, sym in enumerate(symbols):
        if not clib.dxf_add_symbol(sc.subscription, dxf_const_string_t_from_unicode(sym)):
            process_last_error()

def dxf_attach_listener(SubscriptionClass sc):
    """
    Function attaches default listener according to subscription type
    Parameters
    ----------
    sc: SubscriptionClass
        SubscriptionClass with information about subscription
    """
    if not sc.subscription:
        raise ValueError('Subscription is not valid')
    if sc.event_type_str == 'Trade':
        sc.data['columns'] = lis.TRADE_COLUMNS
        sc.listener = lis.trade_default_listener
    elif sc.event_type_str == 'Quote':
        sc.data['columns'] = lis.QUOTE_COLUMNS
        sc.listener = lis.quote_default_listener
    elif sc.event_type_str == 'Summary':
        sc.data['columns'] = lis.SUMMARY_COLUMNS
        sc.listener = lis.summary_default_listener
    elif sc.event_type_str == 'Profile':
        sc.data['columns'] = lis.PROFILE_COLUMNS
        sc.listener = lis.profile_default_listener
    elif sc.event_type_str == 'TimeAndSale':
        sc.data['columns'] = lis.TIME_AND_SALE_COLUMNS
        sc.listener = lis.time_and_sale_default_listener
    elif sc.event_type_str == 'Candle':
        sc.data['columns'] = lis.CANDLE_COLUMNS
        sc.listener = lis.candle_default_listener
    elif sc.event_type_str == 'Order':
        sc.data['columns'] = lis.ORDER_COLUMNS
        sc.listener = lis.order_default_listener
    elif sc.event_type_str == 'TradeETH':
        sc.data['columns'] = lis.TRADE_COLUMNS
        sc.listener = lis.trade_default_listener
    elif sc.event_type_str == 'SpreadOrder':
        sc.data['columns'] = lis.ORDER_COLUMNS
        sc.listener = lis.order_default_listener
    elif sc.event_type_str == 'Greeks':
        sc.data['columns'] = lis.GREEKS_COLUMNS
        sc.listener = lis.greeks_default_listener
    elif sc.event_type_str == 'TheoPrice':
        sc.data['columns'] = lis.THEO_PRICE_COLUMNS
        sc.listener = lis.theo_price_default_listener
    elif sc.event_type_str == 'Underlying':
        sc.data['columns'] = lis.UNDERLYING_COLUMNS
        sc.listener = lis.underlying_default_listener
    elif sc.event_type_str == 'Series':
        sc.data['columns'] = lis.SERIES_COLUMNS
        sc.listener = lis.series_default_listener
    elif sc.event_type_str == 'Configuration':
        sc.data['columns'] = lis.CONFIGURATION_COLUMNS
        sc.listener = lis.configuration_default_listener
    else:
        raise Exception(f'No default listener for {sc.event_type_str} event type')

    if not clib.dxf_attach_event_listener(sc.subscription, sc.listener, sc.u_data):
        process_last_error()

def dxf_attach_custom_listener(SubscriptionClass sc, lis.FuncWrapper fw, columns: list, data: dict = None):
    """
    Attaches custom listener
    Parameters
    ----------
    sc: SubscriptionClass
        SubscriptionClass with information about subscription
    fw: FuncWrapper
        c function wrapped in FuncWrapper class with Cython
    columns: list
        Columns for internal data of SubscriptionClass
    data: dict
        Dict with new internal data structure of  SubscriptionClass
    """
    if not sc.subscription:
        raise ValueError('Subscription is not valid')
    if data:
        sc.data = data
    sc.data['columns'] = columns
    sc.listener = fw.func
    if not clib.dxf_attach_event_listener(sc.subscription, sc.listener, sc.u_data):
        process_last_error()

def dxf_detach_listener(SubscriptionClass sc):
    """
    Detaches any listener
    Parameters
    ----------
    sc: SubscriptionClass
        SubscriptionClass with information about subscription
    """
    if not sc.subscription:
        raise ValueError('Subscription is not valid')
    if not clib.dxf_detach_event_listener(sc.subscription, sc.listener):
        process_last_error()

def dxf_close_connection(ConnectionClass cc):
    """
    Closes connection

    Parameters
    ----------
    cc: ConnectionClass
        Variable with connection information
    """

    # close all subscriptions before closing the connection
    for i in range(cc.sub_ptr_list.size()):
        if cc.sub_ptr_list[i]:  # subscription should not be closed previously
            clib.dxf_close_subscription(cc.sub_ptr_list[i][0])
            cc.sub_ptr_list[i][0] = NULL  # mark subscription as closed

    cc.sub_ptr_list.clear()

    if cc.connection:
        clib.dxf_close_connection(cc.connection)
        cc.connection = NULL

def dxf_close_subscription(SubscriptionClass sc):
    """
    Closes subscription

    Parameters
    ----------
    sc: SubscriptionClass
        SubscriptionClass with information about subscription
    """
    if sc.subscription:
        clib.dxf_close_subscription(sc.subscription)
        sc.subscription = NULL
