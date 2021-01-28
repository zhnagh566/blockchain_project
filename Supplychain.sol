pragma solidity >=0.4.22 <0.6.0;
// pragma solidity ^0.5.11;
pragma experimental ABIEncoderV2;

contract Supplychain{
    struct Company{
        address companyAddr;        //公司地址——主键,此处地址为链上地址，非实际地址
        string name;                //公司名字
        uint creditRating;          //公司信用等级，初始值为0
        bool isValid;               //是否合法，主要判断是否已存在
    }

    //应收款单据
    struct Receipt{
        uint id;                //收据编号——主键
        address from;           //欠款人
    	address to;             //收款人
        uint amount;            //应收款金额
        uint startDate;         //开票日期    
        uint endDate;           //截止日期
        bool isusedLoan;        //是否被用作于向金融机构贷款的信用凭证
        bool isRepay;           //是否已经还钱了
        string description;     //其它备注、描述
    }

    //等待签署的应收款单据
    mapping(uint => Receipt) public pending;

    //Company[]  companys;
    Company[] public banks;                         //参与供应链的银行
    
    //公司到应收帐款的映射
    mapping(address => Receipt[]) public receipts;

    //应收款单据编号 1,2,3,...
    uint receiptId;
    
    //事件
    event ReceiptIssued(address owner, string desc);
    event ReceiptSigned(address who, string desc);
    event Transfered(address fromAddr, address toAddr, uint amount, string desc);
    event Loaned(address who, uint amount, string desc);
    event pay(address fromAddr, address toAddr, uint amount, string desc);


    //生产企业或者金融机构，金融机构包括银行可以认证交易
    mapping(address => Company) public companies;   //参与供应链的公司
    
    //构造函数
    constructor() public {
        receiptId = 1;
    }
    
    //增加公司
    function addCompany(address _company, string _name) public {
        require(
            !companies[_company].isValid,
            "The company already exists."
        );
        companies[_company].companyAddr = _company;
        companies[_company].name = _name;
        companies[_company].creditRating = 0;
        companies[_company].isValid = true;
    }

    //增加银行
    function addBank(string _name, address _addr)public returns(bool){
        banks.push(Company(_addr, _name, 0, true));
        return true;
    }
    

    //功能一：实现采购商品—签发应收账款 交易上链。例如车企从轮胎公司购买一批轮胎并签订应收账款单据。
    //公司发起应收款单据,owner为收款人，client为欠款人
    function IssueReceipt(address owner, address client, uint amount, uint startDate, uint endDate) public returns(uint _id){
        require(
            msg.sender == owner,
            "You don't have permission to issue this receipt!"
        );
        pending[receiptId] = Receipt(receiptId, client, msg.sender, amount, startDate, endDate, false, false, "");
        _id = receiptId;
        receiptId++;
        emit ReceiptIssued(owner, "Receipt Issued");
    }
    
    //客户签署应收款单据
    function SignReceipt(uint _id)public returns(bool){
        Receipt r = pending[_id];
        //签署人必须是该单据的欠款人
        require(
            r.from == msg.sender, 
            "You don't have permission to sign this receipt！"
        );
        //单据未到期
        require(
            now < r.endDate,
            "You have passed the repayment date."
        );
        receipts[r.to].push(Receipt(r.id, r.from, r.to, r.amount, now, r.endDate, false, false, ""));
        emit ReceiptSigned(msg.sender, "Receipt Signed");
        return true;
    }
    
    
    //功能二：实现应收账款的转让上链。
    //轮胎公司从轮毂公司购买一笔轮毂，便将于车企的应收账款单据部分转让给轮毂公司。
    //轮毂公司可以利用这个新的单据去融资或者要求车企到期时归还钱款。
    function TransferTo(uint _receiptid, address to, uint amount) public returns(uint _id){
        Receipt storage senderReceipt;
        for (uint i = 0; i < receipts[msg.sender].length; i++){
            if (receipts[msg.sender][i].id == _receiptid){
                senderReceipt = receipts[msg.sender][i];
                break;
            }
            require(
                i != receipts[msg.sender].length - 1,
                "no such receipt id."
            );
        }

        require(senderReceipt.amount >= amount && amount > 0);
        //转移账款
        senderReceipt.amount -= amount;
        receipts[to].push(Receipt(receiptId, senderReceipt.from, to, amount, now, senderReceipt.endDate, false, false, ""));
        _id = receiptId;
        receiptId++;
        Transfered(msg.sender, to, amount, "transfer successfully");
    }
    
    //功能三：利用应收账款向银行融资上链
    //将应收账款给银行，企业收到现金
    //参数：loanTo（需要融资的企业），loanAmount（贷款数额），receiptid(应收款收据编号)
    function MakeLoan(address loanTo, uint loanAmount, uint receiptid) public returns(bool){
        //只能由银行调用
        uint count = 0;
        uint i;
        for(i = 0; i < banks.length; i++){
            if(banks[i].companyAddr == msg.sender){
                count++;
            }
        }
        require(count == 1);

        //遍历所有的应收账款，找到应收款单据
        Receipt storage rec;
        for(i = 0; i < receipts[loanTo].length; i++){
            if(receipts[loanTo][i].id == receiptid){
                rec = receipts[loanTo][i];
                break;
            }
            require(i != receipts[msg.sender].length - 1, "No such receipt id.");
        }

        //该单据已经被用于贷款
        require(rec.isusedLoan == false, "The receipt has alreadly been used for loan.");
        
        //融资金额不能大于核心公司与该企业之间存在应收账款交易
        require(rec.amount >= loanAmount);
        
        //融资成功
        rec.isusedLoan = true;
        Loaned(loanTo, loanAmount, "Loan Successfully.");
        return true;
    }
    
    function PayForReceipt(address owner, uint amount,uint receiptid) public returns(bool){
        Receipt storage r;
        uint i;
        for (i = 0; i < receipts[owner].length;i++)
        {
            if (receipts[owner][i].id==receiptid)
            {
                r = receipts[owner][i];
                break;
            }
            require(i != receipts[msg.sender].length - 1,"no such receipt id.");
        }
        
        require(r.to == msg.sender,"sender doesn't match receipt's client");
        require(r.amount >= amount,"payment exceeds receipt'amount");
        r.amount -= amount;
        if(r.amount > 0)
            return true;
        for(;i<receipts[owner].length - 1;i++)
        {
            receipts[owner][i] = receipts[owner][i+1];
        }
        delete receipts[owner][i];
        receipts[owner].length--;
        pay(msg.sender, owner, amount,"pay for receipt successfully.");
        return true;
    }

}